# PSMD 工具（PSMD v1.9.1：教学与批量计算）

**PSMD（Peak width of Skeletonized Mean Diffusivity，骨架化平均弥散度峰宽）** 是脑小血管病（SVD）白质损伤的 DTI 标志物：主要白质纤维束骨架内 MD 直方图的 P95−P5 峰宽，反映白质微结构损伤的异质性。全自动、单受试者数分钟、对扫描方案鲁棒。

本仓库将上游 PSMD pipeline v1.9.1 改造为面向医院研究者的工具：**教学 notebook + 批量计算包装**，本地直跑（FSL 依赖），不使用容器。

> [!IMPORTANT]
> **PSMD 已有继任者 [DELTA-SVD](https://delta-svd.com)**——上游仓库已归档停止维护。**两者数值不可混用**于同一分析（同一研究请锁定一个工具）。本工具锁定 **PSMD 1.9.1 数值口径**，适合复现已发表研究与教学。

> [!CAUTION]
> **PSMD 非医疗设备，仅供学术科研使用。** 禁止用于诊断、预后、监测或任何临床常规用途（如欧盟 MDR 第 5 条等法律明文禁止）。

## 这个工具干什么

输入 DTI 数据（三种入口任选其一），输出每受试者的 PSMD 值（或 MSMD、分半球值）：

| 入口 | 参数 | 说明 |
|------|------|------|
| 原始 DWI | `-d DWI -b bvals -r bvecs -s 掩膜` | 引擎内做 `eddy_correct` |
| 预处理 DWI（推荐） | `-p DWI -b bvals -r bvecs -s 掩膜` | 已做形变/运动/涡流校正 |
| 已拟合 FA+MD | `-f FA -m MD -s 掩膜` | 已有 DTI 派生图 |

批处理 `psmd_batch.sh` 在此之上提供：受试者目录遍历、独立 scratch 隔离、CSV 汇总、失败不中断。

## 环境要求

- **FSL ≥ 6.0.7**（TBSS 核心，含 **FSL 许可证**）——安装步骤见 **[docs/install.md](docs/install.md)**
- `dc`（`apt install dc`）
- Python 3.13 + jupyter/nibabel/pandas/matplotlib——`conda env create -f environment.yml`
- Linux/macOS；Windows 用户经 WSL2 使用（无法用 WSL2 的旧机器不适用）

## 快速开始

```bash
conda activate psmd-tool
jupyter lab                      # 从仓库根目录启动
# 打开 notebooks/01-PSMD原理与实操.ipynb，从头运行
```

15–30 分钟跑通 `examples/` 两个示例受试者。示例数据上的实际输出（批处理 CSV，`-f -m` 入口）：

| 受试者 | PSMD（mm²/s） |
|--------|----------------|
| subjectA | 0.000263567（≈ 2.64 ×10⁻⁴） |
| subjectB | 0.000891553（≈ 8.92 ×10⁻⁴） |

文献参考区间（×10⁻⁴ mm²/s）：社区/健康人群 1.54–4.29，CAA 4.38–4.97，CADASIL 5.57–5.63（Zanon Zotin 2023 综述汇总）。预期输出示例见 `outputs_demo/`（批量 CSV + 两张 MD 骨架直方图）。

## 批量计算：psmd_batch.sh

```bash
# 每个受试者一个一级子目录
bash src/psmd_batch.sh -i <受试者根目录> -o <输出CSV> [选项]

# 选项：-s 骨架掩膜（缺省 src/skeleton_mask_2019.nii.gz）
#       -m msmd       改算 MSMD
#       -g            分半球（CSV 列变为 psmd_left,psmd_right）
#       -e <b值>      增强 CSF 掩膜（透传引擎，需 DWI 数据与 FSL≥6.0）
#       -l <病灶掩膜>  病灶区剔除（透传引擎）
```

**受试者数据识别规则**（每个一级子目录内自动识别）：
- `*_FA*.nii.gz` + `*_MD*.nii.gz` 成对存在 → fitted 管线
- 否则 `X.nii.gz + X.bval + X.bvec` 同名三件套 → preprocessed 管线
- 两者皆无 → 记入 CSV 错误行，继续下一个受试者

**CSV 列**：`subject,pipeline,psmd,status,error`（`-g` 时值列为 `psmd_left,psmd_right`；`-m msmd` 时为 `msmd`）

**退出码**：`0` 全部成功 ｜ `1` 用法/环境错误（如 `FSLDIR` 未设置）｜ `2` 有失败受试者（详见 CSV error 列）

## 与知识库的联动

PSMD 方法学（原理、参考区间、偏倚对策）在本知识库 `03_Knowledge` 有系统沉淀；仓库协作者请参考下方引用与延伸阅读 DOI。

## 引用与许可

使用本工具请引用：

- Baykara E, Gesierich B, Adam R, et al. **A novel imaging marker for small vessel disease based on skeletonization of white matter tracts and diffusion histograms.** *Ann Neurol*. 2016;80(4):581-592. [doi:10.1002/ana.24758](https://doi.org/10.1002/ana.24758)（PSMD 原始方法）
- FSL-TBSS 引用指南：<http://fsl.fmrib.ox.ac.uk/fsl/fslwiki/TBSS>
- 方法学综述：Zanon Zotin MC, et al. *Radiology*. 2023;306(3):e212780. [doi:10.1148/radiol.212780](https://doi.org/10.1148/radiol.212780)

**许可**：`psmd.sh` 引擎为 BSD 3-clause（版权与引用要求见 `src/psmd.sh` 头部与 `LICENSE`）；本仓库新增文件（psmd_batch.sh、notebook、docs）同许可证。FSL 需其自身许可证（见 docs/install.md）。

## 目录结构

```
250917_psmd_SP/
├── README.md                 # 本文件
├── LICENSE                   # BSD-3（上游）
├── environment.yml           # Python 环境（conda-forge）
├── docs/
│   └── install.md            # FSL 安装 + 许可证 + dc + 排错
├── src/
│   ├── psmd.sh               # 上游 v1.9.1 引擎（仅修 -g -o 半球 MSMD bug，注释标注）
│   ├── psmd_batch.sh         # 批处理包装 v0.1.0
│   └── skeleton_mask_2019.nii.gz   # 官方推荐骨架掩膜
├── notebooks/
│   ├── 01-PSMD原理与实操.ipynb
│   └── figures/
│       └── Figure-1-PSMD-pipeline-overview.jpg
├── examples/                 # 示例数据（subjectA/B，FA+MD）
└── outputs_demo/             # 预期输出示例
    ├── psmd_batch_examples.csv
    ├── subjectA_MD_skeleton_histogram.png
    └── subjectB_MD_skeleton_histogram.png
```
