# 环境安装指南

本工具的运行环境分两块：**FSL**（影像处理核心，走 FSL 官方安装器，不进 conda）与 **Python**（notebook 教学/绘图环境，用 conda 管理）。

## 1. 前置条件

- Linux 或 macOS；Windows 用户请先安装 **WSL2**（Ubuntu 发行版），所有后续步骤在 WSL2 内进行
  - 无法使用 WSL2 的旧 Windows 机器：本工具不适用
- Anaconda 或 Miniforge（用于第 5 步的 Python 环境）
- 约 10 GB 磁盘空间（FSL 本体约 5–8 GB）

## 2. 安装 FSL 6.0.7

FSL 是 PSMD 流水线（TBSS 骨架化、张量拟合、统计）的核心依赖，**必须**安装 FSL 6.0.7 或更新版本。

```bash
# 官方安装器（Linux/macOS/WSL2 通用）
curl -O https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py
python3 fslinstaller.py
```

安装器默认装到 `/usr/local/fsl`（需 sudo）或用户目录。安装结束后按提示把下面两行加入 `~/.bashrc`：

```bash
export FSLDIR=/usr/local/fsl          # 以实际安装路径为准
source $FSLDIR/etc/fslconf/fsl.sh
export PATH=$FSLDIR/bin:$PATH
```

> 国内网络下载 FSL 较慢时，可参考 FSL 官网下载页选择镜像。

## 3. FSL 许可证（必读）

**FSL 需要许可证**。学术用途可申请免费学术许可证；商业用途需商业许可证。申请入口：

<https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/Licence>

安装许可证后，`fslstats`、`tbss_*` 等命令才能正常工作。**无论以何种方式使用 PSMD，都需要遵守 FSL 许可条款。**

## 4. 安装 dc（小工具，必装）

PSMD 脚本用 `dc`（任意精度计算器）做数值换算：

```bash
# Ubuntu / WSL2
sudo apt install dc
# CentOS / RHEL
sudo yum install dc
# macOS（一般自带，缺时）
brew install dc
```

## 5. Python 环境（notebook 用）

```bash
# 在仓库根目录执行
conda env create -f environment.yml      # 或 mamba env create -f environment.yml
conda activate psmd-tool
```

## 6. 安装自检

```bash
echo $FSLDIR                  # 应输出 FSL 安装路径，非空
command -v fslstats tbss_1_preproc dtifit   # 三条路径都应出现
command -v dc                 # 应输出路径
conda activate psmd-tool && python -c "import nibabel, pandas, matplotlib; print('Python OK')"
```

全部通过后，从仓库根目录启动教学 notebook：

```bash
jupyter lab
```

## 7. 常见报错排查

| 症状 | 原因与处置 |
|------|-----------|
| `ERROR: Skeleton_mask file not found` | 未传 `-s` 骨架掩膜或路径不对。快速开始用仓库自带的 `src/skeleton_mask_2019.nii.gz`；批处理缺省也用它 |
| `ERROR: 'psmdtemp' folder in current directory` | 上次运行的临时目录残留。重跑加 `-c`（自动清理），或手动 `rm -rf psmdtemp` |
| `ERROR: FSL version 6.0 or newer required for enhanced masking` | `-e` 增强 CSF 掩膜需要 FSL ≥ 6.0。升级 FSL 或不用 `-e` |
| `ERROR: This script requires a working installation of FSL` | `FSLDIR` 未设置——回到第 2 步把环境变量写进 `~/.bashrc` 并 `source` |
| 中文/空格目录名报「找不到数据」 | 本工具已处理带空格与中文的路径；若仍报错请确认文件名匹配识别规则（FA+MD 对，或 DWI+bval+bvec 同名三件套） |

---

*本指南适用版本：PSMD 工具 v0.1.0（基于上游 PSMD pipeline v1.9.1）。*
