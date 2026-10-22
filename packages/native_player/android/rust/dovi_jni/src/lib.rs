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
