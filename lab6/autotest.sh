#!/usr/bin/env bash
set -u
set -o pipefail

script_dir="$(pwd)"
result_file="$script_dir/result.txt"
circ_file="$script_dir/lab6.5.circ"
jar_path="$script_dir/Logisim-ITA.jar"

if ! command -v java >/dev/null 2>&1; then
  echo "Error: java not found in PATH."
  exit 1
fi

if [ ! -f "$jar_path" ]; then
  echo "Error: cannot find $jar_path"
  exit 1
fi

: > "$result_file"

shopt -s nullglob # 让 for 循环在没有匹配文件时不执行
for file in "$script_dir"/testcase/*.hex; do
  base_name="$(basename "$file")" # 从路径中提取文件名
  case "$base_name" in
    *_d.hex)
      continue
      ;;
  esac

  echo "Testing $base_name"

  tokens="$({
    awk '
      BEGIN { IGNORECASE = 1 }
      tolower($0) ~ /^v2\.0[[:space:]]+raw$/ { next }
      {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^[0-9A-Fa-f]+$/) {
            print $i
          }
        }
      }
    ' "$file"
  })"

  rom_body="$(printf '%s\n' "$tokens" | awk '
    {
      line = line (line == "" ? "" : " ") $0
      count++
      if (count % 8 == 0) {
        print line
        line = ""
      }
    }
    END {
      if (line != "") print line
    }
  ')"
  new_contents="addr/data: 16 32
$rom_body
"

  test_circ_file="$script_dir/.autotest.$$.$base_name.circ"
  cp "$circ_file" "$test_circ_file"

  NEW_CONTENTS="$new_contents" perl -0pi -e '
    s{(<comp lib="4" loc="\(360,400\)" name="ROM">.*?<a name="contents">).*?(</a>)}{$1 . $ENV{NEW_CONTENTS} . $2}se
  ' "$test_circ_file"

  output_file="$script_dir/.autotest.$$.$base_name.out"
  timeout_status=0
  timeout 100s java -jar "$jar_path" "$test_circ_file" -tty table >"$output_file" 2>&1 || timeout_status=$?

   if [ "$timeout_status" -eq 124 ]; then
    echo "Testing $base_name Timeout" >> "$result_file"
    rm -f "$output_file"
    rm -f "$test_circ_file"
    continue
  fi

  last_line="$(tail -n 1 "$output_file")"
  echo "$base_name : $last_line" >> "$result_file"
  rm -f "$output_file"
  rm -f "$test_circ_file"
done
