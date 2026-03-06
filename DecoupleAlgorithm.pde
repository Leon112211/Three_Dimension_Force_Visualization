// =============================================================================
// DecoupleAlgorithm.pde
// 耦合矩阵加载、矩阵求逆与力解耦运算模块
//
// 数学模型：
//   传感器输出 B_raw（µT）受轴间耦合影响：B_raw = C × F_true
//   其中 C 为耦合矩阵，F_true 为真实三轴力（N）
//   解耦公式：F_decoupled = C^(-1) × ((B_raw - zero_offset) / sensitivity)
// =============================================================================


// ========================== 可配置参数 ========================================

// 耦合矩阵 JSON 文件路径（相对于 sketch 的 data/ 文件夹）
static final String COUPLING_FILE = "coupling_matrix.json";

// 矩阵求逆：行列式绝对值低于此阈值视为奇异矩阵
static final float SINGULAR_THRESHOLD = 1e-6;

// 验证：C × C^(-1) 与单位矩阵的允许最大误差
static final float VALIDATION_TOLERANCE = 1e-4;

// =============================================================================


// ----------------------- 模块内部状态 ----------------------------------------

float[][] couplingMatrix   = new float[3][3]; // 原始耦合矩阵 C（从 JSON 加载）
float[][] decouplingMatrix = new float[3][3]; // 逆矩阵 C^(-1)（求逆后存储）
float[]   zeroOffset       = new float[3];    // 零点偏移（µT）
float[]   sensitivity      = new float[3];    // 各轴灵敏度（µT/N）

boolean decoupleReady = false; // 模块初始化成功标志，其他模块调用前应检查此标志


// =============================================================================
// loadCouplingMatrix()
// 从 JSON 文件加载耦合矩阵和标定参数，计算逆矩阵并初始化模块。
// 必须在 setup() 中调用一次，调用后执行 validateDecoupling() 验证结果。
// =============================================================================
void loadCouplingMatrix() {
  JSONObject json;
  try {
    json = loadJSONObject(COUPLING_FILE);
  } catch (Exception e) {
    println("[DecoupleAlgorithm] 错误：无法加载文件 " + COUPLING_FILE);
    println("  原因：" + e.getMessage());
    println("  请确认文件已放置在 sketch 的 data/ 文件夹内。");
    return;
  }

  // --- 读取 3×3 耦合矩阵 ---
  JSONArray matrixArray = json.getJSONArray("coupling_matrix");
  for (int i = 0; i < 3; i++) {
    JSONArray row = matrixArray.getJSONArray(i);
    for (int j = 0; j < 3; j++) {
      couplingMatrix[i][j] = row.getFloat(j);
    }
  }

  // --- 读取标定参数 ---
  JSONObject calib = json.getJSONObject("calibration");
  JSONArray  offsetArr = calib.getJSONArray("zero_offset");
  JSONArray  sensArr   = calib.getJSONArray("sensitivity");
  for (int i = 0; i < 3; i++) {
    zeroOffset[i]  = offsetArr.getFloat(i);
    sensitivity[i] = sensArr.getFloat(i);
  }

  // --- 计算逆矩阵 ---
  float[][] inv = invertMatrix3x3(couplingMatrix);
  if (inv == null) {
    println("[DecoupleAlgorithm] 错误：耦合矩阵奇异，无法求逆！请检查矩阵数值。");
    return;
  }
  decouplingMatrix = inv;
  decoupleReady    = true;

  println("[DecoupleAlgorithm] 初始化成功");
  _printMatrix("耦合矩阵 C", couplingMatrix);
  _printMatrix("解耦矩阵 C^(-1)", decouplingMatrix);
}


// =============================================================================
// decouple(float[] rawReading)
// 将原始传感器读数解耦为三轴力。
//
// 参数：rawReading — 原始磁场读数 [Bx, By, Bz]，单位 µT
// 返回：解耦后的三轴力 [Fx, Fy, Fz]，单位 N
//       若模块未就绪，返回零向量。
//
// 处理步骤：
//   1. 零点偏移校正：B_corr = B_raw - zero_offset
//   2. 灵敏度换算：  F_raw  = B_corr / sensitivity  （µT → N）
//   3. 矩阵解耦：    F_out  = C^(-1) × F_raw
// =============================================================================
float[] decouple(float[] rawReading) {
  if (!decoupleReady) {
    println("[DecoupleAlgorithm] 警告：模块未初始化，返回零向量。");
    return new float[]{0, 0, 0};
  }

  // 步骤 1：零点偏移校正
  float[] corrected = new float[3];
  for (int i = 0; i < 3; i++) {
    corrected[i] = rawReading[i] - zeroOffset[i];
  }

  // 步骤 2：灵敏度换算（防止除以零）
  float[] fRaw = new float[3];
  for (int i = 0; i < 3; i++) {
    fRaw[i] = (abs(sensitivity[i]) > 1e-9) ? corrected[i] / sensitivity[i] : 0.0;
  }

  // 步骤 3：矩阵解耦
  return matVecMul(decouplingMatrix, fRaw);
}


// =============================================================================
// invertMatrix3x3(float[][] m)
// 使用余子式/伴随矩阵法解析求解 3×3 矩阵的逆。
//
// 参数：m — 3×3 输入矩阵
// 返回：逆矩阵；若矩阵奇异（行列式≈0）则返回 null
// =============================================================================
float[][] invertMatrix3x3(float[][] m) {
  // 按第一行展开计算行列式
  float det = m[0][0] * (m[1][1]*m[2][2] - m[1][2]*m[2][1])
            - m[0][1] * (m[1][0]*m[2][2] - m[1][2]*m[2][0])
            + m[0][2] * (m[1][0]*m[2][1] - m[1][1]*m[2][0]);

  if (abs(det) < SINGULAR_THRESHOLD) {
    println("[DecoupleAlgorithm] 警告：行列式=" + nf(det, 1, 8) + "，矩阵奇异，无法求逆。");
    return null;
  }

  // 计算余子式矩阵并转置（即伴随矩阵），除以行列式得逆矩阵
  float[][] inv = new float[3][3];
  inv[0][0] =  (m[1][1]*m[2][2] - m[1][2]*m[2][1]) / det;
  inv[0][1] = -(m[0][1]*m[2][2] - m[0][2]*m[2][1]) / det;
  inv[0][2] =  (m[0][1]*m[1][2] - m[0][2]*m[1][1]) / det;

  inv[1][0] = -(m[1][0]*m[2][2] - m[1][2]*m[2][0]) / det;
  inv[1][1] =  (m[0][0]*m[2][2] - m[0][2]*m[2][0]) / det;
  inv[1][2] = -(m[0][0]*m[1][2] - m[0][2]*m[1][0]) / det;

  inv[2][0] =  (m[1][0]*m[2][1] - m[1][1]*m[2][0]) / det;
  inv[2][1] = -(m[0][0]*m[2][1] - m[0][1]*m[2][0]) / det;
  inv[2][2] =  (m[0][0]*m[1][1] - m[0][1]*m[1][0]) / det;

  return inv;
}


// =============================================================================
// matVecMul(float[][] mat, float[] vec)
// 3×3 矩阵与 3×1 向量的乘法：result = mat × vec
// =============================================================================
float[] matVecMul(float[][] mat, float[] vec) {
  float[] result = new float[3];
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      result[i] += mat[i][j] * vec[j];
    }
  }
  return result;
}


// =============================================================================
// matMatMul(float[][] a, float[][] b)
// 3×3 × 3×3 矩阵乘法：result = a × b
// =============================================================================
float[][] matMatMul(float[][] a, float[][] b) {
  float[][] result = new float[3][3];
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      for (int k = 0; k < 3; k++) {
        result[i][j] += a[i][k] * b[k][j];
      }
    }
  }
  return result;
}


// =============================================================================
// validateDecoupling()
// 计算 C × C^(-1)，检验结果是否逐元素接近单位矩阵。
// 建议在 loadCouplingMatrix() 之后立即调用，用于快速自检。
//
// 返回：true = 验证通过；false = 误差超出 VALIDATION_TOLERANCE
// =============================================================================
boolean validateDecoupling() {
  if (!decoupleReady) {
    println("[Validate] 跳过：模块未初始化。");
    return false;
  }

  float[][] product = matMatMul(couplingMatrix, decouplingMatrix);
  boolean   passed  = true;

  println("[Validate] C × C^(-1)（应接近单位矩阵）：");
  for (int i = 0; i < 3; i++) {
    print("  [ ");
    for (int j = 0; j < 3; j++) {
      float expected = (i == j) ? 1.0 : 0.0;
      float error    = abs(product[i][j] - expected);
      if (error > VALIDATION_TOLERANCE) passed = false;
      print(nf(product[i][j], 1, 5) + (j < 2 ? "  " : ""));
    }
    println(" ]");
  }

  println("[Validate] 结果：" + (passed ? "通过 ✓" : "失败 ✗（误差 > " + VALIDATION_TOLERANCE + "）"));
  return passed;
}


// =============================================================================
// runUnitTests()
// 内置单元测试，验证各核心函数的正确性。
// 可在 setup() 末尾调用，测试结果输出到控制台。
// =============================================================================
void runUnitTests() {
  println("\n========== DecoupleAlgorithm 单元测试 ==========");
  int passed = 0, total = 0;

  // ------------------------------------------------------------------
  // 测试 1：单位矩阵求逆 → 结果仍为单位矩阵
  // ------------------------------------------------------------------
  total++;
  float[][] I  = {{1,0,0},{0,1,0},{0,0,1}};
  float[][] iI = invertMatrix3x3(I);
  boolean t1 = (iI != null)
             && abs(iI[0][0]-1)<1e-5 && abs(iI[1][1]-1)<1e-5 && abs(iI[2][2]-1)<1e-5
             && abs(iI[0][1])<1e-5   && abs(iI[0][2])<1e-5;
  println("测试1 [单位矩阵求逆]:       " + (t1 ? "通过 ✓" : "失败 ✗"));
  if (t1) passed++;

  // ------------------------------------------------------------------
  // 测试 2：已知矩阵求逆（解析验证）
  //   M = [[2,1,0],[1,3,1],[0,1,2]]，det = 9
  //   M^(-1)[0][0] = 5/9，M^(-1)[0][1] = -2/9
  // ------------------------------------------------------------------
  total++;
  float[][] M  = {{2,1,0},{1,3,1},{0,1,2}};
  float[][] iM = invertMatrix3x3(M);
  boolean t2 = (iM != null)
             && abs(iM[0][0] - 5.0/9) < 1e-5
             && abs(iM[0][1] + 2.0/9) < 1e-5
             && abs(iM[2][2] - 5.0/9) < 1e-5;
  println("测试2 [已知矩阵求逆]:       " + (t2 ? "通过 ✓" : "失败 ✗"));
  if (t2) passed++;

  // ------------------------------------------------------------------
  // 测试 3：奇异矩阵应返回 null
  // ------------------------------------------------------------------
  total++;
  float[][] S   = {{1,2,3},{2,4,6},{0,0,0}}; // 行2 = 2×行1，奇异
  boolean   t3  = (invertMatrix3x3(S) == null);
  println("测试3 [奇异矩阵检测]:       " + (t3 ? "通过 ✓" : "失败 ✗"));
  if (t3) passed++;

  // ------------------------------------------------------------------
  // 测试 4：matVecMul 正确性 — I × [1,2,3] = [1,2,3]
  // ------------------------------------------------------------------
  total++;
  float[] v4  = {1, 2, 3};
  float[] r4  = matVecMul(I, v4);
  boolean t4  = abs(r4[0]-1)<1e-5 && abs(r4[1]-2)<1e-5 && abs(r4[2]-3)<1e-5;
  println("测试4 [矩阵向量乘法]:       " + (t4 ? "通过 ✓" : "失败 ✗"));
  if (t4) passed++;

  // ------------------------------------------------------------------
  // 测试 5：解耦往返验证
  //   构造 B_raw = C × F_test + zero_offset，
  //   经 decouple() 还原后应等于 F_test
  // ------------------------------------------------------------------
  total++;
  if (decoupleReady) {
    float[] fTest = {3.0, -1.5, 10.0};

    // 模拟含耦合的传感器输出（sensitivity=[1,1,1] 时 µT = N）
    float[] bRaw = matVecMul(couplingMatrix, fTest);
    for (int i = 0; i < 3; i++) bRaw[i] += zeroOffset[i];

    float[] fRecovered = decouple(bRaw);
    boolean t5 = abs(fRecovered[0]-fTest[0])<1e-3
              && abs(fRecovered[1]-fTest[1])<1e-3
              && abs(fRecovered[2]-fTest[2])<1e-3;

    println("测试5 [解耦往返验证]:");
    println("  输入力:    [" + nf(fTest[0],1,3)      + ", " + nf(fTest[1],1,3)      + ", " + nf(fTest[2],1,3)      + "] N");
    println("  还原力:    [" + nf(fRecovered[0],1,4) + ", " + nf(fRecovered[1],1,4) + ", " + nf(fRecovered[2],1,4) + "] N");
    println("  结果: " + (t5 ? "通过 ✓" : "失败 ✗"));
    if (t5) passed++;
  } else {
    println("测试5 [解耦往返验证]:       跳过（耦合矩阵未加载）");
  }

  println("-------------------------------------------------");
  println("测试汇总：" + passed + " / " + total + " 通过");
  println("=================================================\n");
}


// =============================================================================
// _printMatrix()  — 内部辅助函数，打印矩阵到控制台
// =============================================================================
void _printMatrix(String label, float[][] m) {
  println("[DecoupleAlgorithm] " + label + ":");
  for (int i = 0; i < 3; i++) {
    println("  [ " + nf(m[i][0],1,5) + "  " + nf(m[i][1],1,5) + "  " + nf(m[i][2],1,5) + " ]");
  }
}
