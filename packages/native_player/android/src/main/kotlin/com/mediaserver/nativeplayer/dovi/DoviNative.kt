package com.mediaserver.nativeplayer.dovi

/**
 * libdovi（rust/dovi_jni）解析 RPU 的结果，长度 [LENGTH]：
 * [0] 有效标记，[1] profile，[2..5) YCC→LMS 偏移，[5..14) YCC→L'M'S' 矩阵（行优先），
 * [14..23) LMS→BT.2020 RGB 矩阵（行优先），[23] source_min_pq，[24] source_max_pq（0..1），
 * [25..29) L6：母版最大 / 最小亮度、MaxCLL、MaxFALL（nits，没有 L6 时为 0）；
 * 之后每个分量 [COMP_LENGTH]：[0] 节点数，[1..10) 节点（0..1），
 * 每段 [PIECE_LENGTH]：[0] 方法（0 多项式 / 1 MMR），[1..4) 多项式系数，[4] MMR 阶数，[5] MMR 常数，[6..27) MMR 系数（阶 × 7）
 */
object DoviNative {
  const val MAX_PIVOTS = 9
  const val MAX_PIECES = 8
  const val PIECE_LENGTH = 27
  const val COMP_LENGTH = 1 + MAX_PIVOTS + MAX_PIECES * PIECE_LENGTH
  const val HEADER_LENGTH = 29
  const val LENGTH = HEADER_LENGTH + 3 * COMP_LENGTH

  init {
    System.loadLibrary("dovi_jni")
  }

  /** 传入完整的 NAL 62（以 0x7C01 开头，含防竞争字节），失败返回 null，原因见 [lastError] */
  external fun parse(nal: ByteArray): FloatArray?

  external fun lastError(): String
}
