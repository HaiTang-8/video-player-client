//! 用 libdovi 解析杜比视界 RPU，转成着色器直接可用的参数（布局见 `DoviNative.kt`）。

use std::cell::RefCell;
use std::panic::{catch_unwind, AssertUnwindSafe};

use dolby_vision::rpu::dovi_rpu::DoviRpu;
use dolby_vision::rpu::extension_metadata::blocks::ExtMetadataBlock;
use dolby_vision::rpu::rpu_data_header::RpuDataHeader;
use dolby_vision::rpu::rpu_data_mapping::DoviReshapingCurve;
use jni::objects::{JByteArray, JClass};
use jni::sys::{jfloatArray, jstring};
use jni::JNIEnv;

const MAX_PIVOTS: usize = 9;
const MAX_PIECES: usize = 8;
const PIECE_LEN: usize = 27;
const COMP_LEN: usize = 1 + MAX_PIVOTS + MAX_PIECES * PIECE_LEN;
const HEADER_LEN: usize = 29;
const LEN: usize = HEADER_LEN + 3 * COMP_LEN;

/// BT.2020 HPE LMS → RGB，与 RPU 中的 rgb_to_lms 矩阵相乘后得到最终的 LMS → RGB
const LMS_TO_RGB: [[f64; 3]; 3] = [
    [3.06441879, -2.16597676, 0.10155818],
    [-0.65612108, 1.78554118, -0.12943749],
    [0.01736321, -0.04725154, 1.03004253],
];

/// RPU 没有 VDR DM 数据时使用的默认值（与 FFmpeg 的 ff_dovi_color_default 一致）
const DEFAULT_YCC_TO_RGB: [i16; 9] = [9575, 0, 14742, 9575, 1754, 4383, 9575, 17372, 0];
const DEFAULT_YCC_OFFSET: [f64; 3] = [0.25, 2.0, 2.0];
const DEFAULT_RGB_TO_LMS: [i16; 9] = [5845, 9702, 837, 2568, 12256, 1561, 0, 679, 15705];

thread_local! {
    static LAST_ERROR: RefCell<String> = const { RefCell::new(String::new()) };
}

#[no_mangle]
pub extern "system" fn Java_com_mediaserver_nativeplayer_dovi_DoviNative_parse<'l>(
    env: JNIEnv<'l>,
    _class: JClass<'l>,
    data: JByteArray<'l>,
) -> jfloatArray {
    let Ok(bytes) = env.convert_byte_array(&data) else {
        return std::ptr::null_mut();
    };
    let result = catch_unwind(AssertUnwindSafe(|| convert(&bytes)))
        .unwrap_or_else(|_| Err("libdovi panicked".to_string()));
    match result {
        Ok(values) => match env.new_float_array(LEN as i32) {
            Ok(array) => {
                if env.set_float_array_region(&array, 0, &values).is_err() {
                    return std::ptr::null_mut();
                }
                array.into_raw()
            }
            Err(_) => std::ptr::null_mut(),
        },
        Err(message) => {
            LAST_ERROR.with(|e| *e.borrow_mut() = message);
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "system" fn Java_com_mediaserver_nativeplayer_dovi_DoviNative_lastError<'l>(
    env: JNIEnv<'l>,
    _class: JClass<'l>,
) -> jstring {
    let message = LAST_ERROR.with(|e| e.borrow().clone());
    env.new_string(message)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

fn convert(nal: &[u8]) -> Result<[f32; LEN], String> {
    let rpu = DoviRpu::parse_unspec62_nalu(nal).map_err(|e| e.to_string())?;
    let header = &rpu.header;
    let mapping = rpu
        .rpu_data_mapping
        .as_ref()
        .ok_or("RPU reuses the previous mapping")?;
    let mut out = [0f32; LEN];
    out[0] = 1.0;
    out[1] = rpu.dovi_profile as f32;

    let (ycc_to_rgb, offsets, rgb_to_lms, min_pq, max_pq) = match &rpu.vdr_dm_data {
        Some(dm) => (
            [
                dm.ycc_to_rgb_coef0, dm.ycc_to_rgb_coef1, dm.ycc_to_rgb_coef2,
                dm.ycc_to_rgb_coef3, dm.ycc_to_rgb_coef4, dm.ycc_to_rgb_coef5,
                dm.ycc_to_rgb_coef6, dm.ycc_to_rgb_coef7, dm.ycc_to_rgb_coef8,
            ],
            [dm.ycc_to_rgb_offset0, dm.ycc_to_rgb_offset1, dm.ycc_to_rgb_offset2]
                .map(|o| o as f64 / (1u64 << 28) as f64),
            [
                dm.rgb_to_lms_coef0, dm.rgb_to_lms_coef1, dm.rgb_to_lms_coef2,
                dm.rgb_to_lms_coef3, dm.rgb_to_lms_coef4, dm.rgb_to_lms_coef5,
                dm.rgb_to_lms_coef6, dm.rgb_to_lms_coef7, dm.rgb_to_lms_coef8,
            ],
            dm.source_min_pq,
            dm.source_max_pq,
        ),
        None => (DEFAULT_YCC_TO_RGB, DEFAULT_YCC_OFFSET, DEFAULT_RGB_TO_LMS, 62, 3696),
    };
    for i in 0..3 {
        out[2 + i] = offsets[i] as f32;
    }
    for i in 0..9 {
        out[5 + i] = ycc_to_rgb[i] as f32 / 8192.0;
    }
    for row in 0..3 {
        for col in 0..3 {
            let value: f64 = (0..3)
                .map(|k| LMS_TO_RGB[row][k] * rgb_to_lms[k * 3 + col] as f64 / 16384.0)
                .sum();
            out[14 + row * 3 + col] = value as f32;
        }
    }
    out[23] = min_pq as f32 / 4095.0;
    out[24] = max_pq as f32 / 4095.0;
    if let Some(ExtMetadataBlock::Level6(l6)) = rpu.vdr_dm_data.as_ref().and_then(|dm| dm.get_block(6)) {
        out[25] = l6.max_display_mastering_luminance as f32;
        out[26] = l6.min_display_mastering_luminance as f32 / 10000.0;
        out[27] = l6.max_content_light_level as f32;
        out[28] = l6.max_frame_average_light_level as f32;
    }

    for (c, curve) in mapping.curves.iter().enumerate() {
        write_curve(header, curve, &mut out[HEADER_LEN + c * COMP_LEN..][..COMP_LEN])
            .map_err(|e| format!("component {c}: {e}"))?;
    }
    Ok(out)
}

fn write_curve(header: &RpuDataHeader, curve: &DoviReshapingCurve, out: &mut [f32]) -> Result<(), String> {
    let num_pivots = curve.pivots.len();
    if !(2..=MAX_PIVOTS).contains(&num_pivots) {
        return Err(format!("{num_pivots} pivots"));
    }
    let pieces = num_pivots - 1;
    let bl_max = ((1u32 << (header.bl_bit_depth_minus8 + 8)) - 1) as f32;
    out[0] = num_pivots as f32;
    let mut pivot = 0u32;
    for (i, delta) in curve.pivots.iter().enumerate() {
        pivot += *delta as u32;
        out[1 + i] = pivot as f32 / bl_max;
    }

    let coef = |int: i64, frac: u64| -> f32 {
        if header.coefficient_data_type == 0 {
            (int as f64 + frac as f64 / (1u64 << header.coefficient_log2_denom) as f64) as f32
        } else {
            f32::from_bits(frac as u32)
        }
    };
    let pieces_out = |p: usize| 1 + MAX_PIVOTS + p * PIECE_LEN;

    match (&curve.polynomial, &curve.mmr) {
        (Some(poly), None) => {
            if poly.poly_coef.len() != pieces {
                return Err("polynomial piece count mismatch".into());
            }
            for p in 0..pieces {
                let base = pieces_out(p);
                out[base] = 0.0;
                for k in 0..poly.poly_coef[p].len() {
                    out[base + 1 + k] = coef(poly.poly_coef_int[p][k], poly.poly_coef[p][k]);
                }
            }
        }
        (None, Some(mmr)) => {
            if mmr.mmr_constant.len() != pieces {
                return Err("MMR piece count mismatch".into());
            }
            for p in 0..pieces {
                let base = pieces_out(p);
                let order = mmr.mmr_order_minus1[p] as usize + 1;
                out[base] = 1.0;
                out[base + 4] = order as f32;
                out[base + 5] = coef(mmr.mmr_constant_int[p], mmr.mmr_constant[p]);
                for j in 0..order {
                    for k in 0..7 {
                        out[base + 6 + j * 7 + k] = coef(mmr.mmr_coef_int[p][j][k], mmr.mmr_coef[p][j][k]);
                    }
                }
            }
        }
        _ => return Err("mixed or missing mapping method".into()),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use dolby_vision::rpu::rpu_data_mapping::{DoviMMRCurve, DoviMappingMethod};
    use tinyvec::ArrayVec;

    const TEST_MKV_FRAME0: &[u8] = include_bytes!("../tests/fixtures/test_mkv_frame0.rpu");
    const MYSTIC9_SEEK590: &[u8] = include_bytes!("../tests/fixtures/mystic9_seek590.rpu");
    const DENOM: f32 = (1u32 << 23) as f32;

    fn comp(out: &[f32], c: usize) -> &[f32] {
        &out[HEADER_LEN + c * COMP_LEN..][..COMP_LEN]
    }

    fn piece(out: &[f32], c: usize, p: usize) -> &[f32] {
        &comp(out, c)[1 + MAX_PIVOTS + p * PIECE_LEN..][..PIECE_LEN]
    }

    fn assert_close(actual: f32, expected: f32) {
        assert!((actual - expected).abs() <= 1e-6 * expected.abs().max(1.0), "{actual} != {expected}");
    }

    /// 期望值来自 FFmpeg 9 对同一帧的解码（ffprobe -show_frames）
    fn assert_color_and_luma(out: &[f32], pivots: &[u16], first: [i64; 3]) {
        assert_eq!(out[1], 5.0);
        let nonlinear = [8192, 799, 1681, 8192, -933, 1091, 8192, 267, -5545];
        for (i, v) in nonlinear.iter().enumerate() {
            assert_close(out[5 + i], *v as f32 / 8192.0);
        }
        assert_close(out[2], 0.0);
        assert_close(out[3], 0.5);
        assert_close(out[4], 0.5);
        let rgb_to_lms = [17081, -349, -349, -349, 17081, -349, -349, -349, 17081];
        for row in 0..3 {
            for col in 0..3 {
                let expected: f64 = (0..3)
                    .map(|k| LMS_TO_RGB[row][k] * rgb_to_lms[k * 3 + col] as f64 / 16384.0)
                    .sum();
                assert_close(out[14 + row * 3 + col], expected as f32);
            }
        }
        assert_close(out[23], 7.0 / 4095.0);
        assert_close(out[24], 3079.0 / 4095.0);
        assert_eq!(comp(out, 0)[0] as usize, pivots.len());
        for (i, p) in pivots.iter().enumerate() {
            assert_close(comp(out, 0)[1 + i], *p as f32 / 1023.0);
        }
        let p0 = piece(out, 0, 0);
        assert_eq!(p0[0], 0.0);
        for k in 0..3 {
            assert_close(p0[1 + k], first[k] as f32 / DENOM);
        }
    }

    #[test]
    fn converts_test_mkv_frame0_like_ffmpeg() {
        let out = convert(TEST_MKV_FRAME0).unwrap();
        assert_color_and_luma(&out, &[0, 23, 86, 217, 468, 724, 953, 1014, 1020], [4822, 15311232, -194342976]);
        for c in 1..3 {
            assert_eq!(comp(&out, c)[0], 2.0);
            assert_close(comp(&out, c)[2], 1.0);
            let p = piece(&out, c, 0);
            assert_close(p[1], 4194304.0 / DENOM);
            assert_close(p[2], 0.0);
        }
    }

    #[test]
    fn converts_mystic9_frame_like_ffmpeg() {
        let out = convert(MYSTIC9_SEEK590).unwrap();
        assert_color_and_luma(&out, &[0, 23, 77, 304, 497, 753, 920, 1000, 1021], [5917, 16388770, -214826016]);
        let last = piece(&out, 0, 7);
        for (k, v) in [4426276i64, -2922704, 4167512].iter().enumerate() {
            assert_close(last[1 + k], *v as f32 / DENOM);
        }
        for (c, coefs) in [(1, [-1194364i64, 11394808]), (2, [-1247977, 11372980])] {
            let p = piece(&out, c, 0);
            assert_close(p[1], coefs[0] as f32 / DENOM);
            assert_close(p[2], coefs[1] as f32 / DENOM);
        }
        // 本片带 L6：母版 1000 / 0.0001 nits，MaxCLL 1455，MaxFALL 539
        assert_eq!(&out[25..29], &[1000.0, 0.0001, 1455.0, 539.0]);
    }

    /// 与着色器一致的 CPU 实现：选段、多项式或 MMR、按首尾节点截断
    fn reshape(out: &[f32], c: usize, sig: [f32; 3]) -> f32 {
        let comp = comp(out, c);
        let count = comp[0] as usize;
        let s = sig[c];
        let index = (1..count - 1).filter(|i| s >= comp[1 + i]).last().unwrap_or(0);
        let p = piece(out, c, index);
        let r = if p[0] == 0.0 {
            (p[3] * s + p[2]) * s + p[1]
        } else {
            let (x, y, z) = (sig[0], sig[1], sig[2]);
            let terms = [x, y, z, x * y, x * z, y * z, x * y * z];
            let mut r = p[5];
            for order in 0..p[4] as usize {
                for (k, t) in terms.iter().enumerate() {
                    r += p[6 + order * 7 + k] * t.powi(order as i32 + 1);
                }
            }
            r
        };
        r.clamp(comp[1], comp[count])
    }

    /// 把多项式改写成等价的 MMR（常数 + 本分量一次项 + 本分量平方项），验证 MMR 的解析和求值
    #[test]
    fn polynomial_rewritten_as_mmr_reshapes_identically() {
        let mut rpu = DoviRpu::parse_unspec62_nalu(MYSTIC9_SEEK590).unwrap();
        let mapping = rpu.rpu_data_mapping.as_mut().unwrap();
        for (c, curve) in mapping.curves.iter_mut().enumerate() {
            let poly = curve.polynomial.take().unwrap();
            let mut mmr = DoviMMRCurve::default();
            for p in 0..poly.poly_coef.len() {
                let int = |k: usize| poly.poly_coef_int[p].get(k).copied().unwrap_or(0);
                let frac = |k: usize| poly.poly_coef[p].get(k).copied().unwrap_or(0);
                mmr.mmr_order_minus1.push(1);
                mmr.mmr_constant_int.push(int(0));
                mmr.mmr_constant.push(frac(0));
                let mut ints: ArrayVec<[ArrayVec<[i64; 7]>; 3]> = ArrayVec::new();
                let mut fracs: ArrayVec<[ArrayVec<[u64; 7]>; 3]> = ArrayVec::new();
                for order in 0..2 {
                    let mut i7: ArrayVec<[i64; 7]> = ArrayVec::new();
                    let mut f7: ArrayVec<[u64; 7]> = ArrayVec::new();
                    for k in 0..7 {
                        let own = k == c;
                        i7.push(if own { int(order + 1) } else { 0 });
                        f7.push(if own { frac(order + 1) } else { 0 });
                    }
                    ints.push(i7);
                    fracs.push(f7);
                }
                mmr.mmr_coef_int.push(ints);
                mmr.mmr_coef.push(fracs);
            }
            curve.mapping_idc = DoviMappingMethod::MMR;
            curve.mmr = Some(mmr);
        }
        rpu.modified = true;
        let nal = rpu.write_hevc_unspec62_nalu().unwrap();
        let original = convert(MYSTIC9_SEEK590).unwrap();
        let rewritten = convert(&nal).unwrap();
        for c in 0..3 {
            assert_eq!(piece(&rewritten, c, 0)[0], 1.0);
            assert_eq!(piece(&rewritten, c, 0)[4], 2.0);
        }
        for yi in 0..=16 {
            for ci in 0..=8 {
                let sig = [yi as f32 / 16.0, ci as f32 / 8.0, 1.0 - ci as f32 / 8.0];
                for c in 0..3 {
                    let a = reshape(&original, c, sig);
                    let b = reshape(&rewritten, c, sig);
                    assert!((a - b).abs() < 1e-5, "component {c} at {sig:?}: {a} vs {b}");
                }
            }
        }
    }

    #[test]
    fn rejects_garbage() {
        assert!(convert(&[0x7c, 0x01, 0x19, 0x08, 0x09, 0, 0, 0]).is_err());
    }
}
