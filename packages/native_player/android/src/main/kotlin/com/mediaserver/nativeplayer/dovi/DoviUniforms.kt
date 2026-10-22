package com.mediaserver.nativeplayer.dovi

import android.opengl.GLES30
import com.mediaserver.nativeplayer.dovi.DoviNative.COMP_LENGTH
import com.mediaserver.nativeplayer.dovi.DoviNative.HEADER_LENGTH
import com.mediaserver.nativeplayer.dovi.DoviNative.MAX_PIECES
import com.mediaserver.nativeplayer.dovi.DoviNative.MAX_PIVOTS
import com.mediaserver.nativeplayer.dovi.DoviNative.PIECE_LENGTH

/** 把 [DoviNative.parse] 的结果整理成着色器 uniform（GL 线程使用） */
class DoviUniforms {
  private val numPivots = IntArray(3)
  private val pivots = FloatArray(MAX_PIVOTS * 3)
  private val coeffs = FloatArray(3 * MAX_PIECES * 4)
  private val mmr = FloatArray(3 * MAX_PIECES * 6 * 4)
  private val offset = FloatArray(3)
  private val nonlinear = FloatArray(9)
  private val lmsToRgb = FloatArray(9)

  fun pack(params: FloatArray) {
    params.copyInto(offset, 0, 2, 5)
    params.copyInto(nonlinear, 0, 5, 14)
    params.copyInto(lmsToRgb, 0, 14, 23)
    coeffs.fill(0f)
    mmr.fill(0f)
    for (c in 0 until 3) {
      val comp = HEADER_LENGTH + c * COMP_LENGTH
      val count = params[comp].toInt()
      numPivots[c] = count
      for (i in 0 until MAX_PIVOTS) pivots[i * 3 + c] = params[comp + 1 + i]
      for (p in 0 until count - 1) {
        val piece = comp + 1 + MAX_PIVOTS + p * PIECE_LENGTH
        val slot = (c * MAX_PIECES + p) * 4
        if (params[piece] == 0f) {
          params.copyInto(coeffs, slot, piece + 1, piece + 4)
        } else {
          val order = params[piece + 4].toInt()
          coeffs[slot] = params[piece + 5]
          coeffs[slot + 3] = order.toFloat()
          for (j in 0 until order) {
            val src = piece + 6 + j * 7
            val dst = ((c * MAX_PIECES + p) * 6 + j * 2) * 4
            params.copyInto(mmr, dst, src, src + 3)
            params.copyInto(mmr, dst + 4, src + 3, src + 7)
          }
        }
      }
    }
  }

  fun upload(program: Int) {
    fun location(name: String) = GLES30.glGetUniformLocation(program, name)
    GLES30.glUniform3iv(location("uNumPivots"), 1, numPivots, 0)
    GLES30.glUniform3fv(location("uPivots"), MAX_PIVOTS, pivots, 0)
    GLES30.glUniform4fv(location("uCoeffs"), 3 * MAX_PIECES, coeffs, 0)
    GLES30.glUniform4fv(location("uMmr"), 3 * MAX_PIECES * 6, mmr, 0)
    GLES30.glUniform3fv(location("uOffset"), 1, offset, 0)
    GLES30.glUniformMatrix3fv(location("uNonlinear"), 1, true, nonlinear, 0)
    GLES30.glUniformMatrix3fv(location("uLmsToRgb"), 1, true, lmsToRgb, 0)
  }

  companion object {
    /**
     * 杜比视界重建：原始 YCbCr（全范围归一化）→ 分段多项式 / MMR 重建 → L'M'S'（PQ）→ LMS → BT.2020 RGB → PQ。
     * uCoeffs.w 为 0 表示多项式（xyz 为系数），否则为 MMR 阶数（x 为常数项）；uMmr 每阶两个 vec4：一次项、交叉项
     */
    const val RESHAPE_SHADER =
      """#version 300 es
#extension GL_OES_EGL_image_external_essl3 : require
#extension GL_EXT_YUV_target : require
precision highp float;
precision highp int;
uniform __samplerExternal2DY2YEXT uTex;
uniform ivec3 uNumPivots;
uniform vec3 uPivots[9];
uniform vec4 uCoeffs[24];
uniform vec4 uMmr[144];
uniform vec3 uOffset;
uniform mat3 uNonlinear;
uniform mat3 uLmsToRgb;
in vec2 vTex;
out vec4 outColor;

const float M1 = 2610.0 / 16384.0;
const float M2 = 2523.0 / 4096.0 * 128.0;
const float C1 = 3424.0 / 4096.0;
const float C2 = 2413.0 / 4096.0 * 32.0;
const float C3 = 2392.0 / 4096.0 * 32.0;

vec3 pqEotf(vec3 v) {
  vec3 p = pow(max(v, 0.0), vec3(1.0 / M2));
  return pow(max(p - C1, 0.0) / (C2 - C3 * p), vec3(1.0 / M1));
}

vec3 pqOetf(vec3 v) {
  vec3 p = pow(max(v, 0.0), vec3(M1));
  return pow((C1 + C2 * p) / (1.0 + C3 * p), vec3(M2));
}

float reshape(int c, vec3 sig) {
  float s = sig[c];
  int count = uNumPivots[c];
  int piece = 0;
  for (int i = 1; i < 8; i++) {
    if (i < count - 1 && s >= uPivots[i][c]) piece = i;
  }
  int index = c * 8 + piece;
  vec4 k = uCoeffs[index];
  float r;
  if (k.w == 0.0) {
    r = (k.z * s + k.y) * s + k.x;
  } else {
    int m = index * 6;
    vec4 sigX = vec4(sig.xxy * sig.yzz, sig.x * sig.y * sig.z);
    r = k.x + dot(uMmr[m].xyz, sig) + dot(uMmr[m + 1], sigX);
    if (k.w >= 2.0) {
      vec3 sig2 = sig * sig;
      vec4 sigX2 = sigX * sigX;
      r += dot(uMmr[m + 2].xyz, sig2) + dot(uMmr[m + 3], sigX2);
      if (k.w >= 3.0) r += dot(uMmr[m + 4].xyz, sig2 * sig) + dot(uMmr[m + 5], sigX2 * sigX);
    }
  }
  return clamp(r, uPivots[0][c], uPivots[count - 1][c]);
}

void main() {
  vec3 sig = clamp(texture(uTex, vTex).xyz, 0.0, 1.0);
  vec3 v = vec3(reshape(0, sig), reshape(1, sig), reshape(2, sig));
  vec3 lms = pqEotf(uNonlinear * (v - uOffset));
  outColor = vec4(clamp(pqOetf(uLmsToRgb * lms), 0.0, 1.0), 1.0);
}
"""
  }
}
