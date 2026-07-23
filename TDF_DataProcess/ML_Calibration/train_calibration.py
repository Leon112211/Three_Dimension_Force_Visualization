# -*- coding: utf-8 -*-
"""
四方案标定对比实验: 线性基准 vs 二次多项式 vs 直接 MLP vs 残差学习

数据: TDF_DataProcess/Raw_Data 的单轴分级加载标定数据 (8 个 传感器x轴 组合)
输入: ΔB = 逐帧磁场 - 零力级均值 (3 通道), 输出: 施力轴力值 F (N)

防泄漏设计 (核心):
  - 训练/测试严格按 **力级** 划分, 同一力级的所有帧只进一侧;
  - Z 轴 (41 级): 4 折交叉 -- 内部级按 idx%4 轮流留出, 端点 (0N / 满量程) 恒在训练集
    (只考察插值, 不做外推);
  - X/Y 轴 (7 级): 留一力级交叉 (5 个内部级各留一次);
  - 标准化只在训练集拟合; 训练帧每级限采 MAX_TRAIN_PER_LEVEL, 测试帧全保留。

统计口径 (经独立对抗审查后确定):
  - rmse_mean: 所有 (折 x 种子) 逐帧 RMSE 的均值;
  - rmse_fold_std: 各折"种子均值 RMSE"的折间标准差 (图 1 误差棒, 四方法口径一致);
  - rmse_seed_spread: 折内种子间标准差的均值 (优化器噪声, 确定性模型为 0);
  - max_level_err 按 **单种子** 折外级均值曲线计算, 报告 种子均值 与 最差种子
    (不做种子集成 -- 部署时只有一个网络);
  - 图 2/3 的级曲线为种子平均 (图题注明), 供看形态; 数值以表格口径为准;
  - results.json 保留每 (折, 种子) 原始 RMSE 与每种子级预测, 可复核。

伪影处理: Z-H2 在 15->15.5N 之间有夹具移位台阶, 额外跑 0-15N 剔除版本 (trim15)。
收敛性: lbfgs 迭代上限 3000; 不静默收敛警告, 逐变体计数并打印。

输出: results/ 下 results.json / results.csv + 四张图 (图内文字为英文, 便于论文复用)。
"""

import json
import sys
import time
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from sklearn.exceptions import ConvergenceWarning
from sklearn.linear_model import LinearRegression, Ridge
from sklearn.neural_network import MLPRegressor
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import PolynomialFeatures, StandardScaler

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from process_sensitivity import AXES_CONFIG, force_to_filename, read_raw_csv  # noqa: E402

RESULTS = HERE / 'results'
RESULTS.mkdir(exist_ok=True)

SEEDS = [0, 1, 2, 3, 4]          # MLP / 残差学习的重复种子
MAX_TRAIN_PER_LEVEL = 200        # 每个训练力级最多采样的帧数
MLP_MAX_ITER = 3000
FULL_SCALE = {'X': 3.0, 'Y': 3.0, 'Z': 20.0}
MODELS = ['linear', 'quadratic', 'mlp', 'residual']
MODEL_LABEL = {'linear': 'Linear', 'quadratic': 'Quadratic',
               'mlp': 'MLP', 'residual': 'Residual (Lin+MLP)'}
MODEL_COLOR = {'linear': '#9AA5B1', 'quadratic': '#1F77B4',
               'mlp': '#D62728', 'residual': '#2CA02C'}

PAIRS = [(axis, sensor) for axis, cfg in AXES_CONFIG.items() for sensor in cfg['sensors']]


# ---------------------------------------------------------------- 数据加载
def load_pair(axis: str, sensor: str) -> pd.DataFrame:
    """逐帧数据: 列 F, dBx, dBy, dBz, level_idx (按力值排序的力级编号)"""
    cfg = AXES_CONFIG[axis]
    sensor_dir = cfg['dir'] / f"{cfg['prefix']}_{sensor}"
    frames = {}
    for force in cfg['forces']:
        df = read_raw_csv(sensor_dir / f"{force_to_filename(force)}.csv")
        frames[force] = df[['x1', 'y1', 'z1']].to_numpy(float)
    baseline = frames[0.0].mean(axis=0)   # 零力级恒在训练集 (端点), 无泄漏
    rows = []
    for idx, force in enumerate(sorted(frames)):
        db = frames[force] - baseline
        block = np.column_stack([np.full(len(db), force), db,
                                 np.full(len(db), idx)])
        rows.append(block)
    data = pd.DataFrame(np.vstack(rows),
                        columns=['F', 'dBx', 'dBy', 'dBz', 'level_idx'])
    data['level_idx'] = data['level_idx'].astype(int)
    return data


def make_folds(n_levels: int, axis: str):
    """返回 [(test_idx_list), ...]; 端点 0 和 n-1 永远在训练集。"""
    interior = list(range(1, n_levels - 1))
    if axis == 'Z':
        return [[i for i in interior if i % 4 == off] for off in range(4)]
    return [[i] for i in interior]          # X/Y: 留一力级


# ---------------------------------------------------------------- 模型
def fit_predict(model_name: str, seed: int,
                Xtr: np.ndarray, ytr: np.ndarray, Xte: np.ndarray) -> np.ndarray:
    if model_name == 'linear':
        m = LinearRegression().fit(Xtr, ytr)
        return m.predict(Xte)
    if model_name == 'quadratic':
        m = make_pipeline(StandardScaler(),
                          PolynomialFeatures(2, include_bias=False),
                          Ridge(alpha=1e-3)).fit(Xtr, ytr)
        return m.predict(Xte)
    if model_name == 'mlp':
        m = make_pipeline(StandardScaler(),
                          MLPRegressor(hidden_layer_sizes=(16, 16),
                                       activation='relu', solver='lbfgs',
                                       alpha=1e-4, max_iter=MLP_MAX_ITER,
                                       random_state=seed)).fit(Xtr, ytr)
        return m.predict(Xte)
    if model_name == 'residual':
        lin = LinearRegression().fit(Xtr, ytr)
        resid = ytr - lin.predict(Xtr)
        cor = make_pipeline(StandardScaler(),
                            MLPRegressor(hidden_layer_sizes=(16, 16),
                                         activation='relu', solver='lbfgs',
                                         alpha=1e-4, max_iter=MLP_MAX_ITER,
                                         random_state=seed)).fit(Xtr, resid)
        return lin.predict(Xte) + cor.predict(Xte)
    raise ValueError(model_name)


# ---------------------------------------------------------------- 实验主体
def run_variant(tag: str, axis: str, sensor: str, data: pd.DataFrame) -> dict:
    levels = sorted(data['level_idx'].unique())
    n = len(levels)
    forces = data.groupby('level_idx')['F'].first().sort_index().to_numpy()
    folds = make_folds(n, axis)
    fs = FULL_SCALE[axis]

    out = {m: {'records': [], 'seed_level_pred': {}} for m in MODELS}
    noise_frames = []
    conv_warnings = 0

    for fold_id, test_levels in enumerate(folds):
        train_mask = ~data['level_idx'].isin(test_levels)
        test_df = data[~train_mask]
        # 每个训练力级限采帧数 (信息在级均值, 限采控制训练成本); 四模型共用同一训练集
        rng = np.random.default_rng(1000 + fold_id)
        parts = []
        for lv, grp in data[train_mask].groupby('level_idx'):
            take = min(len(grp), MAX_TRAIN_PER_LEVEL)
            parts.append(grp.iloc[rng.permutation(len(grp))[:take]])
        train_df = pd.concat(parts)

        Xtr = train_df[['dBx', 'dBy', 'dBz']].to_numpy()
        ytr = train_df['F'].to_numpy()
        Xte = test_df[['dBx', 'dBy', 'dBz']].to_numpy()
        yte = test_df['F'].to_numpy()
        te_levels = test_df['level_idx'].to_numpy()

        for name in MODELS:
            seeds = SEEDS if name in ('mlp', 'residual') else [0]
            for seed in seeds:
                with warnings.catch_warnings(record=True) as wlist:
                    warnings.simplefilter('always', ConvergenceWarning)
                    pred = fit_predict(name, seed, Xtr, ytr, Xte)
                conv_warnings += sum(1 for w in wlist
                                     if issubclass(w.category, ConvergenceWarning))
                rmse = float(np.sqrt(np.mean((pred - yte) ** 2)))
                out[name]['records'].append(
                    {'fold': fold_id, 'seed': seed, 'rmse': rmse})
                slp = out[name]['seed_level_pred'].setdefault(seed, {})
                for lv in test_levels:      # 每个内部级恰好被一折留出 -> 无覆盖冲突
                    slp[int(lv)] = float(pred[te_levels == lv].mean())
                if name == 'linear':
                    for lv in test_levels:  # 噪声底: 线性模型级内预测波动
                        noise_frames.append(float(pred[te_levels == lv].std()))

    summary = {'tag': tag, 'axis': axis, 'sensor': sensor,
               'n_levels': n, 'full_scale': fs,
               'noise_N': float(np.median(noise_frames)),
               'convergence_warnings': conv_warnings,
               'level_forces': {int(i): float(f) for i, f in enumerate(forces)},
               'models': {}}

    for name in MODELS:
        recs = out[name]['records']
        vals = np.array([r['rmse'] for r in recs])
        n_folds = len(folds)
        fold_means = np.array([np.mean([r['rmse'] for r in recs if r['fold'] == f])
                               for f in range(n_folds)])
        seed_spreads = [np.std([r['rmse'] for r in recs if r['fold'] == f])
                        for f in range(n_folds)]

        # 单种子折外级曲线 -> 每种子的最大级均值误差 (不做种子集成)
        per_seed_maxerr = []
        for seed, lp in out[name]['seed_level_pred'].items():
            per_seed_maxerr.append(max(abs(v - forces[lv]) for lv, v in lp.items()))
        # 图用: 种子平均级预测 (图题注明)
        all_lv = sorted({lv for lp in out[name]['seed_level_pred'].values()
                         for lv in lp})
        ens_pred = {lv: float(np.mean([lp[lv] for lp in
                                       out[name]['seed_level_pred'].values()
                                       if lv in lp])) for lv in all_lv}

        summary['models'][name] = {
            'rmse_mean': float(vals.mean()),
            'rmse_fold_std': float(fold_means.std()),
            'rmse_seed_spread': float(np.mean(seed_spreads)),
            'rmse_pct_fs': float(vals.mean() / fs * 100),
            'max_level_err_mean': float(np.mean(per_seed_maxerr)),
            'max_level_err_worst': float(np.max(per_seed_maxerr)),
            'level_pred': {str(k): v for k, v in ens_pred.items()},
            'rmse_records': recs,
            'seed_level_pred': {str(s): {str(k): v for k, v in lp.items()}
                                for s, lp in out[name]['seed_level_pred'].items()},
        }
    return summary


def main():
    t0 = time.perf_counter()
    print('=' * 66)
    print('  四方案标定对比: 线性 vs 二次多项式 vs MLP vs 残差学习')
    print('=' * 66)

    all_results = []
    for axis, sensor in PAIRS:
        data = load_pair(axis, sensor)
        variants = [(f'{axis}-{sensor}', data)]
        if axis == 'Z' and sensor == 'H2':      # 伪影剔除版本 (0-15N)
            trimmed = data[data['F'] <= 15.0].copy()
            variants.append((f'{axis}-{sensor}-trim15', trimmed))
        for tag, d in variants:
            print(f'\n[{tag}] {len(d):,} 帧 / {d["level_idx"].nunique()} 力级 ...',
                  flush=True)
            res = run_variant(tag, axis, sensor, d)
            all_results.append(res)
            for name in MODELS:
                m = res['models'][name]
                print(f"  {MODEL_LABEL[name]:<20} RMSE {m['rmse_mean']:.4f}"
                      f" (折间±{m['rmse_fold_std']:.4f}, 种子±{m['rmse_seed_spread']:.4f})"
                      f" N ({m['rmse_pct_fs']:.2f}%FS)"
                      f"  单种子最大级误差 均值 {m['max_level_err_mean']:.4f}"
                      f" / 最差 {m['max_level_err_worst']:.4f} N")
            print(f"  (噪声底 ≈ {res['noise_N']:.4f} N,"
                  f" 收敛警告 {res['convergence_warnings']} 次)")

    with open(RESULTS / 'results.json', 'w', encoding='utf-8') as f:
        json.dump(all_results, f, ensure_ascii=False, indent=1)

    rows = []
    for res in all_results:
        for name in MODELS:
            m = res['models'][name]
            rows.append({'variant': res['tag'], 'axis': res['axis'],
                         'sensor': res['sensor'], 'model': name,
                         'rmse_N': round(m['rmse_mean'], 4),
                         'rmse_fold_std': round(m['rmse_fold_std'], 4),
                         'rmse_seed_spread': round(m['rmse_seed_spread'], 4),
                         'rmse_pct_fs': round(m['rmse_pct_fs'], 3),
                         'max_level_err_mean_N': round(m['max_level_err_mean'], 4),
                         'max_level_err_worst_N': round(m['max_level_err_worst'], 4),
                         'noise_floor_N': round(res['noise_N'], 4)})
    pd.DataFrame(rows).to_csv(RESULTS / 'results.csv', index=False)
    print(f'\n结果已写入 {RESULTS}\\results.json / results.csv')

    make_figures(all_results)
    print(f'总耗时 {time.perf_counter() - t0:.0f} s')


# ---------------------------------------------------------------- 图表
def _get(all_results, tag):
    return next(r for r in all_results if r['tag'] == tag)


def make_figures(all_results):
    plt.style.use('seaborn-v0_8-whitegrid')

    # 图 1: Z 轴 RMSE 分组柱状图 (误差棒 = 折间标准差, 四方法口径一致)
    tags = ['Z-H2', 'Z-H2-trim15', 'Z-H4', 'Z-H6']
    fig, ax = plt.subplots(figsize=(9, 4.6))
    xpos = np.arange(len(tags))
    width = 0.2
    for k, name in enumerate(MODELS):
        vals = [_get(all_results, t)['models'][name]['rmse_mean'] for t in tags]
        errs = [_get(all_results, t)['models'][name]['rmse_fold_std'] for t in tags]
        ax.bar(xpos + (k - 1.5) * width, vals, width, yerr=errs, capsize=3,
               label=MODEL_LABEL[name], color=MODEL_COLOR[name])
    ax.set_xticks(xpos)
    ax.set_xticklabels(['Z-H2\n(full 0-20 N)', 'Z-H2\n(0-15 N, artifact removed)',
                        'Z-H4', 'Z-H6'])
    ax.set_ylabel('Held-out RMSE (N)')
    ax.set_title('Force-reconstruction error on held-out force levels (Z axis)\n'
                 'error bars: fold-to-fold std of seed-mean RMSE', fontsize=11)
    ax.legend(ncol=4, fontsize=9)
    fig.tight_layout()
    fig.savefig(RESULTS / 'fig1_rmse_comparison.png', dpi=160)
    plt.close(fig)

    # 图 2: 预测-真值散点 (Z-H4 vs Z-H6; MLP/残差为 5 种子平均曲线)
    fig, axes = plt.subplots(1, 2, figsize=(10.5, 4.8))
    for ax, tag in zip(axes, ['Z-H4', 'Z-H6']):
        res = _get(all_results, tag)
        forces = {int(k): v for k, v in res['level_forces'].items()}
        for name in MODELS:
            lp = res['models'][name]['level_pred']
            xs = [forces[int(k)] for k in lp]
            ys = list(lp.values())
            ax.scatter(xs, ys, s=26, alpha=0.85, label=MODEL_LABEL[name],
                       color=MODEL_COLOR[name])
        lim = [0, res['full_scale']]
        ax.plot(lim, lim, 'k--', lw=1, alpha=0.6)
        ax.set_xlabel('True force (N)')
        ax.set_ylabel('Predicted force (N)')
        ax.set_title(f'{tag}: out-of-fold level-mean predictions\n'
                     '(MLP/Residual: 5-seed average)', fontsize=10)
        ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(RESULTS / 'fig2_pred_vs_true.png', dpi=160)
    plt.close(fig)

    # 图 3: 残差-力曲线 (Z 三对, 全量程版本; MLP/残差为 5 种子平均)
    fig, axes = plt.subplots(1, 3, figsize=(13.5, 4.2), sharey=False)
    for ax, tag in zip(axes, ['Z-H2', 'Z-H4', 'Z-H6']):
        res = _get(all_results, tag)
        forces = {int(k): v for k, v in res['level_forces'].items()}
        for name in MODELS:
            lp = res['models'][name]['level_pred']
            pts = sorted((forces[int(k)], v - forces[int(k)]) for k, v in lp.items())
            ax.plot([p[0] for p in pts], [p[1] for p in pts], marker='o', ms=3,
                    lw=1.4, label=MODEL_LABEL[name], color=MODEL_COLOR[name])
        ax.axhline(0, color='k', lw=0.8, alpha=0.6)
        ax.set_xlabel('True force (N)')
        ax.set_title(tag)
        if tag == 'Z-H2':
            ax.set_ylabel('Prediction error (N)')
            ax.legend(fontsize=8)
    fig.suptitle('Out-of-fold prediction error vs load (Z axis; '
                 'MLP/Residual curves are 5-seed means)', y=1.02)
    fig.tight_layout()
    fig.savefig(RESULTS / 'fig3_residual_curves.png', dpi=160, bbox_inches='tight')
    plt.close(fig)

    # 图 4: 数据总览 -- 主通道 ΔB-F 级均值 + 线性拟合 (曲率与伪影可视化)
    fig, axes = plt.subplots(1, 3, figsize=(13.5, 4.2))
    for ax, sensor in zip(axes, ['H2', 'H4', 'H6']):
        data = load_pair('Z', sensor)
        g = data.groupby('F')['dBz'].mean()
        F, B = g.index.to_numpy(), g.to_numpy()
        a, b = np.polyfit(F, B, 1)
        ax.scatter(F, B, s=16, color='#2CA02C', zorder=3, label='level means')
        ax.plot(F, a * F + b, color='#9AA5B1', lw=1.6, label='linear fit')
        ss_res = np.sum((B - (a * F + b)) ** 2)
        ss_tot = np.sum((B - B.mean()) ** 2)
        ax.set_title(f'Z-{sensor}   R$^2$={1 - ss_res / ss_tot:.4f}')
        ax.set_xlabel('Applied force (N)')
        if sensor == 'H2':
            ax.set_ylabel(r'$\Delta B_z$ ($\mu$T)')
            ax.legend(fontsize=8)
    fig.suptitle('Main-channel response vs load: curvature and the Z-H2 artifact',
                 y=1.02)
    fig.tight_layout()
    fig.savefig(RESULTS / 'fig4_data_overview.png', dpi=160, bbox_inches='tight')
    plt.close(fig)

    print('图表已生成: fig1_rmse_comparison / fig2_pred_vs_true / '
          'fig3_residual_curves / fig4_data_overview')


if __name__ == '__main__':
    main()
