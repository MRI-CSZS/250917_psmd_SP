#!/bin/bash
#
# psmd_batch.sh — PSMD 批处理包装（MRI-CSZS fork, 2026-10）
# 遍历受试者根目录，逐个调用 psmd.sh 引擎（v1.9.1），汇总结果为 CSV。
#
# 本脚本与 psmd.sh 同许可证（BSD 3-clause，见仓库 LICENSE 与 psmd.sh 头部声明）。
# PSMD 非医疗设备，仅供科研使用。
#
# 用法：
#   psmd_batch.sh -i <受试者根目录> -o <输出CSV> [-s <骨架掩膜>] [-m psmd|msmd]
#                 [-g] [-e <b值>] [-l <病灶掩膜>]
#
# 受试者识别规则（-i 下每个非隐藏一级子目录）：
#   fitted 管线      存在 *_FA*.nii.gz 且 *_MD*.nii.gz（各取首个）
#   preprocessed 管线 存在同名三件套 X.nii.gz + X.bval + X.bvec（fitted 不成立时尝试）
#   两者皆无          记为错误行，继续处理下一个受试者
#
# 退出码：0=全部成功  1=用法/环境错误  2=存在失败受试者

usage(){
cat <<USAGE

psmd_batch.sh — PSMD 批处理包装 v0.1.0
包装 src/psmd.sh（PSMD v1.9.1）计算骨架化平均弥散度峰宽

用法：
  psmd_batch.sh -i <受试者根目录> -o <输出CSV> [选项]

必选：
  -i <目录>   受试者根目录，其下每个一级子目录视为一个受试者
  -o <CSV>    输出 CSV 路径（UTF-8，含表头）

可选：
  -s <掩膜>   骨架掩膜（缺省：脚本同目录的 skeleton_mask_2019.nii.gz）
  -m <指标>   psmd（缺省）或 msmd（对应引擎 -o）
  -g          分半球输出（透传引擎 -g）
  -e <b值>    增强 CSF 掩膜（透传引擎 -e；需 DWI 数据与 FSL>=6.0）
  -l <掩膜>   病灶掩膜剔除（透传引擎 -l）
  -h          本帮助

CSV 列（按调用 flag 变化）：
  默认      subject,pipeline,psmd,status,error
  -g        subject,pipeline,psmd_left,psmd_right,status,error
  -m msmd   subject,pipeline,msmd,status,error（-g 时为 msmd_left,msmd_right）
  pipeline ∈ {fitted, preprocessed, unknown}；status ∈ {ok, error}
  （数据无法识别时 pipeline=unknown，仍写入 error 行）

示例：
  psmd_batch.sh -i /data/subjects -o psmd_results.csv
  psmd_batch.sh -i /data/subjects -o psmd_hemis.csv -g -m msmd

USAGE
exit 1
}

SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
ENGINE="$SCRIPT_DIR/psmd.sh"

# 每受试者 scratch 兜底清理（正常路径末尾也会删除）
scratch=""
cleanup(){ [ -n "${scratch:-}" ] && rm -rf "$scratch"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---------- 参数解析 ----------
unset input_dir output_csv metric skeleton_mask
hemispheres=false
enhmask_b=""
lesion_mask=""
while getopts ":i:o:s:m:g:e:l:h" opt; do
  case $opt in
    i) input_dir=${OPTARG} ;;
    o) output_csv=${OPTARG} ;;
    s) skeleton_mask=${OPTARG} ;;
    m) metric=${OPTARG} ;;
    g) hemispheres=true ;;
    e) enhmask_b=${OPTARG} ;;
    l) lesion_mask=${OPTARG} ;;
    h) usage ;;
    \?) echo "ERROR: 无效选项 -$OPTARG。输入 psmd_batch.sh -h 查看帮助" >&2; exit 1 ;;
    :)  echo "ERROR: 选项 -$OPTARG 需要参数。输入 psmd_batch.sh -h 查看帮助" >&2; exit 1 ;;
  esac
done

# ---------- 用法与环境校验 ----------
[ -z "$input_dir" ] || [ -z "$output_csv" ] && { echo "ERROR: 必须提供 -i <受试者根目录> 与 -o <输出CSV>。见 docs/install.md 与 psmd_batch.sh -h" >&2; exit 1; }
[ -d "$input_dir" ] || { echo "ERROR: 受试者根目录不存在: $input_dir" >&2; exit 1; }
[ -x "$ENGINE" ] || { echo "ERROR: 找不到 psmd.sh 引擎: $ENGINE" >&2; exit 1; }

# FSLDIR 预检：引擎依赖 FSL，先于任何 TBSS 计算快速失败
if [ -z "${FSLDIR}" ]; then
  echo "ERROR: FSLDIR 未设置——本工具依赖 FSL（TBSS/dtifit/fslstats）。" >&2
  echo "       请安装 FSL 6.0+ 并完成环境配置，详见 docs/install.md。" >&2
  exit 1
fi

# 掩膜缺省与校验
if [ -z "$skeleton_mask" ]; then
  skeleton_mask="$SCRIPT_DIR/skeleton_mask_2019.nii.gz"
fi
[ -r "$skeleton_mask" ] || { echo "ERROR: 骨架掩膜不可读: $skeleton_mask" >&2; exit 1; }
skeleton_mask=$(readlink -f "$skeleton_mask")

# 指标模式
metric_flag=""
metric_name="psmd"
if [ "$metric" == "msmd" ]; then
  metric_flag="-o"
  metric_name="msmd"
elif [ -n "$metric" ] && [ "$metric" != "psmd" ]; then
  echo "ERROR: -m 仅接受 psmd 或 msmd（收到: $metric）" >&2; exit 1
fi

# 可选透传 flags（数组，避免含空格/中文的路径被词分割）
pass_flags=()
[ "$hemispheres" == true ] && pass_flags+=(-g)
[ -n "$enhmask_b" ] && pass_flags+=(-e "$enhmask_b")
[ -n "$lesion_mask" ] && { [ -r "$lesion_mask" ] || { echo "ERROR: 病灶掩膜不可读: $lesion_mask" >&2; exit 1; }; pass_flags+=(-l "$(readlink -f "$lesion_mask")"); }

# ---------- CSV 表头 ----------
if [ "$hemispheres" == true ]; then
  header="subject,pipeline,${metric_name}_left,${metric_name}_right,status,error"
else
  header="subject,pipeline,${metric_name},status,error"
fi
printf '%s\n' "$header" > "$output_csv"

# ---------- 受试者遍历 ----------
total=0; failed=0
for subj_dir in "$input_dir"/*/; do
  [ -d "$subj_dir" ] || continue
  subj_name=$(basename "$subj_dir")
  total=$((total+1))

  # 识别管线：优先 fitted（FA+MD 对），否则 preprocessed（DWI+bval+bvec）
  fa_file=""; md_file=""
  for f in "$subj_dir"*FA*.nii.gz; do [ -r "$f" ] && { fa_file="$f"; break; }; done
  for f in "$subj_dir"*MD*.nii.gz; do [ -r "$f" ] && { md_file="$f"; break; }; done

  engine_args=()
  pipeline=""
  if [ -n "$fa_file" ] && [ -n "$md_file" ]; then
    pipeline="fitted"
    engine_args+=(-f "$(readlink -f "$fa_file")" -m "$(readlink -f "$md_file")")
  else
    # preprocessed: 同名三件套 X.nii.gz + X.bval + X.bvec
    dwi_base=""
    for f in "$subj_dir"*.nii.gz; do
      [ -r "$f" ] || continue
      base="${f%.nii.gz}"
      [ -r "${base}.bval" ] && [ -r "${base}.bvec" ] && { dwi_base="$base"; break; }
    done
    if [ -n "$dwi_base" ]; then
      pipeline="preprocessed"
      engine_args+=(-p "$(readlink -f "${dwi_base}.nii.gz")" -b "$(readlink -f "${dwi_base}.bval")" -r "$(readlink -f "${dwi_base}.bvec")")
    fi
  fi

  if [ -z "$engine_args" ]; then
    failed=$((failed+1))
    printf '%s,%s,,error,%s\n' "$subj_name" "unknown" "未找到可识别数据（FA+MD 对或 DWI+bval+bvec）" >> "$output_csv"
    echo "  [错误] $subj_name: 未找到可识别数据，跳过" >&2
    continue
  fi

  # scratch 隔离：引擎在 CWD 建 psmdtemp，必须每受试者独立目录
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/psmd_batch.XXXXXX")
  (
    cd "$scratch" || exit 1
    bash "$ENGINE" "${engine_args[@]}" -s "$skeleton_mask" $metric_flag "${pass_flags[@]}" -q > stdout.txt 2> stderr.txt
    echo $? > exit_code.txt
  )

  code=$(cat "$scratch/exit_code.txt" 2>/dev/null)
  result=$(tail -n 1 "$scratch/stdout.txt" 2>/dev/null | tr -d '\r')
  if [ "$code" == "0" ] && [ -n "$result" ]; then
    printf '%s,%s,%s,ok,\n' "$subj_name" "$pipeline" "$result" >> "$output_csv"
  else
    failed=$((failed+1))
    err=$(tail -n 1 "$scratch/stderr.txt" 2>/dev/null | tr -d '\r' | tr ',' ';' | cut -c1-200)
    [ -z "$err" ] && err="引擎退出码 $code，无错误输出"
    printf '%s,%s,,error,%s\n' "$subj_name" "$pipeline" "$err" >> "$output_csv"
    echo "  [错误] $subj_name: $err" >&2
  fi
  rm -rf "$scratch"
  scratch=""
done

# ---------- 结果汇总 ----------
if [ "$total" -eq 0 ]; then
  echo "WARNING: 输入目录下没有受试者子目录: $input_dir" >&2
fi
if [ "$failed" -gt 0 ]; then
  echo "完成：$total 个受试者，$failed 个失败。结果已写入 $output_csv" >&2
  exit 2
fi
echo "完成：$total 个受试者全部成功。结果已写入 $output_csv" >&2
exit 0
