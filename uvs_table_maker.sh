#!/bin/bash

# UVS table maker
#
# Copyright (c) 2023 omonomo
#
# 異体字に対応するため、フォント生成時に失われたUVS情報を復元させるファイルを作成するプログラム
#
# 生成フォントのGSUBテーブルを利用して、
# 漢字用フォントのglyph番号を生成フォントのglyph番号に置き換え、
# 新しいcmapテーブル(format_14)を作成する


# ログをファイル出力させる場合は有効にする (<< "#LOG" をコメントアウトさせる)
<< "#LOG"
LOG_OUT=/tmp/uvs_table_maker.log
LOG_ERR=/tmp/uvs_table_maker_err.log
exec 1> >(tee -a $LOG_OUT)
exec 2> >(tee -a $LOG_ERR)
#LOG

fromFontName="BIZUDGothic-Regular" # 抽出元フォント名
font_familyname="Viroit" # 生成フォントファミリー名

cmapList="cmapList" # 異体字セレクタリスト
extList="extList" # 異体字のglyphナンバーリスト
gsubList="gsubList" # 作成フォントのGSUBから抽出した置き換え用リスト
findUv="9022" # 異体字の先頭文字コード
samplingNum="324" # 取り出すglyphナンバーの数

leaving_tmp_flag="false" # 一時ファイル残す

fonts_directories=". ${HOME}/.fonts /usr/local/share/fonts /usr/share/fonts \
${HOME}/Library/Fonts /Library/Fonts \
/c/Windows/Fonts /cygdrive/c/Windows/Fonts"

remove_temp() {
  echo "Remove temporary files"
  rm -f ${fromFontName}*.ttx
  rm -f ${toFontName}*.ttx
}

uvs_table_maker_help()
{
    echo "Usage: uvs_table_maker.sh [options]"
    echo ""
    echo "Options:"
    echo "  -h         Display this information"
    echo "  -x         Cleaning temporary files" # 一時作成ファイルの消去のみ
    echo "  -l         Leave (do NOT remove) temporary files"
    echo "  -N string  Set fontfamily (\"string\")"
}

# 設定読み込み
settings="settings" # 設定ファイル名
settings_txt=$(find . -maxdepth 1 -name "${settings}.txt" | head -n 1)
if [ -n "${settings_txt}" ]; then
    S=$(grep -m 1 "^FONT_FAMILYNAME=" "${settings_txt}") # フォントファミリー名
    if [ -n "${S}" ]; then font_familyname="${S#FONT_FAMILYNAME=}"; fi
fi

echo
echo "- UVS table [cmap, format 14] maker -"
echo

# Get options
while getopts hxlN: OPT
do
    case "${OPT}" in
        "h" )
            uvs_table_maker_help
            exit 0
            ;;
        "x" )
            echo "Option: Cleaning temporary files"
            remove_temp
            exit 0
            ;;
        "l" )
            echo "Option: Leave (do NOT remove) temporary files"
            leaving_tmp_flag="true"
            ;;
        "N" )
            echo "Option: Set fontfamily: ${OPTARG}"
            font_familyname=${OPTARG// /}
            ;;
        * )
            uvs_table_maker_help
            exit 1
            ;;
    esac
done
echo

toFontName="${font_familyname}-Regular" # 生成フォント名

# フォントがあるかチェック
tmp=""
for i in $fonts_directories
do
    [ -d "${i}" ] && tmp="${tmp} ${i}"
done
fonts_directories=$tmp
fromFontName_ttf=$(find ${fonts_directories} -follow -name "${fromFontName}.ttf" | head -n 1)
if [ -z "${fromFontName_ttf}" ]; then
  echo "Error: ${fromFontName} not found" >&2
  exit 1
fi
toFontName_ttf=$(find . -maxdepth 1 -name "${toFontName}.ttf" | head -n 1)
if [ -z "${toFontName_ttf}" ]; then
  echo "Error: ${toFontName} not found" >&2
  exit 1
fi

# ttxファイルとtxtファイルを削除
rm -f ${fromFontName}.ttx ${fromFontName}.ttx.bak
rm -f ${toFontName}.ttx ${toFontName}.ttx.bak
rm -f ${cmapList}.txt ${cmapList}.txt.bak
rm -f ${extList}.txt ${extList}.txt.bak
rm -f ${gsubList}.txt ${gsubList}.txt.bak

# ttxファイルを生成
ttx -t cmap "${fromFontName_ttf}"
ttx -t GSUB "${toFontName_ttf}"
# 元フォントがカレントディレクトリに無ければ生成したttxファイルを移動
fromFontName_ttx=$(find ${fonts_directories} -follow -name "${fromFontName}.ttx" | head -n 1)
if [ -n "${fromFontName_ttx}" ] && [ ${fromFontName_ttx} != "./${fromFontName}.ttx" ]; then
  echo "Move ${fromFontName}.ttx"
  mv ${fromFontName_ttx} ./
fi
echo

# ttxファイルを移動させる前に異常終了した場合、ttxファイルを消去する
trap "if [ -e \"$fromFontName_ttx\" ]; then echo 'Remove ttx file'; rm -f $fromFontName_ttx; echo 'Abnormally terminated'; fi; exit 3" HUP INT QUIT
trap "if [ -e \"$fromFontName_ttx\" ]; then echo 'Remove ttx file'; rm -f $fromFontName_ttx; echo 'Abnormally terminated'; fi" EXIT

# 元のフォントのcmapから異体字セレクタリスト(format_14)を取り出す
echo "Make cmap List"

grep "map uv=" "${fromFontName}.ttx" >> "${cmapList}.txt"

# 取り出したリストから外字のみのリストを作成
echo "Make external char list"
line=$(grep -m 1 "map uv=\"0x${findUv}\"" "${cmapList}.txt")
temp=${line#*glyph} # glyphナンバーより前を削除
fromNum=${temp%\"*} # glyphナンバーより後を削除
echo "${fromFontName}: 0x${findUv} -> glyph${fromNum}"

for i in $(seq 0 ${samplingNum})
do
  grep "glyph$((fromNum + i))" "${cmapList}.txt" >> "${extList}.txt"
done

# 作成するフォントのGSUBから置換用リストを作成
echo "Make GSUB list"
line=$(grep -m 1 "Substitution in=\"uni${findUv}\"" "${toFontName}.ttx")
temp=${line#*glyph} # glyphナンバーより前を削除
toNum=${temp%\"*} # glyphナンバーより後を削除
echo "${toFontName}: 0x${findUv} -> glyph${toNum}"

for i in $(seq 0 ${samplingNum})
do
  grep -m 1 "glyph$((toNum + i))" "${toFontName}.ttx" >> "${gsubList}.txt"
done

# 異体字セレクタリストのglyphナンバーを置換用リストの物に置き換える
echo "Modify cmap list"
i=1
while read toLine
do
  fromLine=$(head -n ${i} "${extList}.txt" | tail -n 1)
  temp=${fromLine#*glyph} # glyphナンバーより前を削除
  fromNum=${temp%\"*} # glyphナンバーより後を削除

  temp=${toLine##*glyph} # glyphナンバーより前を削除
  toNum=${temp%\"*} # glyphナンバーより後を削除

  sed -i.bak -e "s/glyph${fromNum}/glyph${toNum}/g" "${cmapList}.txt"
  i=$((i + 1))
done < "${gsubList}.txt"
echo

# 一時ファイルを削除
rm -f ${fromFontName}.ttx.bak
rm -f ${toFontName}.ttx.bak
rm -f ${cmapList}.txt.bak
rm -f ${extList}.txt.bak
rm -f ${gsubList}.txt.bak
if [ "${leaving_tmp_flag}" = "true" ]; then
  mv "${fromFontName}.ttx" "${fromFontName}.cmap.orig.ttx"
  mv "${toFontName}.ttx" "${toFontName}.GSUB.orig.ttx"
else
  remove_temp
  echo
fi

# Exit
echo "Finished making the modified table [cmap_format_14]."
echo
exit 0
