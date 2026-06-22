from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path


RESULT_FILE = "result_py.txt"
CIRC_FILE = "lab6.5.circ"
TIMEOUT_SECONDS = 100


def read_hex_tokens(path: Path) -> list[str]:
    tokens: list[str] = []
    with path.open("r", encoding="utf-8-sig", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            tokens.extend(line.split())

    return [token for token in tokens if re.fullmatch(r"[0-9A-Fa-f]+", token)]


def build_rom_contents(tokens: list[str]) -> str:
    rom_lines = [" ".join(tokens[i : i + 8]) for i in range(0, len(tokens), 8)]
    return "addr/data: 16 32\n" + "\n".join(rom_lines) + "\n"


def replace_rom_contents(circ_text: str, contents: str) -> str:
    pattern = re.compile(
        r'(<comp lib="5" loc="\((?:500,660)\)" name="ROM">.*?<a name="contents">)'
        r"(.*?)"
        r"(</a>)",
        re.DOTALL,
    )

    new_text, count = pattern.subn(rf"\1{contents}\3", circ_text, count=1)
    if count == 0:
        raise ValueError('Cannot find ROM contents block at loc="(500,660)".')
    return new_text


def cleanup(paths: list[Path]) -> None:
    for path in paths:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def cleanup_autotest_files(script_dir: Path) -> None:
    for path in script_dir.glob(".autotest.*"):
        if path.is_file():
            try:
                path.unlink()
            except OSError:
                pass


def parse_result_line(line: str) -> list[int]:
    parts = line.replace("\t", " ").split(" ")
    assert len(parts) == 29, f"Unexpected result line format: {line}"
    res = []
    for i in range(7):
        res.append("".join(parts[4*i: 4*i + 4]))
    return [int(x, 2) for x in res]


def is_passed(line: str) -> bool:
    return line.replace("\t", " ").split(" ")[-1] == "1"

def main() -> int:
    script_dir = Path(__file__).resolve().parent
    jar_path = script_dir / "Logisim-ITA.jar"
    circ_path = script_dir / CIRC_FILE
    result_path = script_dir / RESULT_FILE
    testcase_dir = script_dir / "testcase"

    if shutil.which("java") is None:
        print("Error: 'java' not found in PATH. 请安装 Java 或将其加入 PATH。")
        return 1

    if not jar_path.exists():
        print(f"Error: 找不到 {jar_path} 。请确认 Logisim-ITA.jar 在脚本目录中。")
        return 1

    if not circ_path.exists():
        print(f"Error: 找不到 {circ_path} 。请确认 {CIRC_FILE} 在脚本目录中。")
        return 1

    try:
        result_path.unlink()
    except FileNotFoundError:
        pass

    hex_files = sorted(
        path
        for path in testcase_dir.glob("*.hex")
        if path.is_file() and not path.name.endswith("_d.hex") and not (path.stem+"_d.hex" in [f.name for f in testcase_dir.glob("*.hex")])
    )

    with result_path.open("a", encoding="utf-8") as f:
        f.write(f"测试指令 \t & RS2转发次数 \t & RS1转发次数 \t & 分支指令数 \t & 跳转指令数 \t & 冲刷次数 \t & 阻塞次数 \t & 总周期数 \t & 是否通过 \n")

    for hex_file in hex_files:
        print(f"Testing {hex_file.name}")

        tokens = read_hex_tokens(hex_file)
        new_contents = build_rom_contents(tokens)

        try:
            orig = circ_path.read_text(encoding="utf-8-sig", errors="ignore")
            new_circ = replace_rom_contents(orig, new_contents)
        except Exception as exc:
            with result_path.open("a", encoding="utf-8") as f:
                f.write(f"Testing {hex_file.name} Failed: {exc}\n")
            continue

        base = f".autotest.{os.getpid()}.{hex_file.stem}"
        test_circ_file = script_dir / f"{base}.circ"
        stdout_file = script_dir / f"{base}.stdout.txt"
        stderr_file = script_dir / f"{base}.stderr.txt"
        temp_files = [test_circ_file, stdout_file, stderr_file]

        test_circ_file.write_text(new_circ, encoding="utf-8")

        with stdout_file.open("w", encoding="utf-8", errors="ignore") as stdout, stderr_file.open(
            "w", encoding="utf-8", errors="ignore"
        ) as stderr:

            proc = subprocess.Popen(
                ["java", "-jar", str(jar_path), str(test_circ_file), "-tty", "table"],
                cwd=script_dir,
                stdout=stdout,
                stderr=stderr,
                text=True,
            )

            try:
                proc.wait(timeout=TIMEOUT_SECONDS)
                finished = True
            except subprocess.TimeoutExpired:
                finished = False
                proc.kill()
                proc.wait()

        if not finished:
            with result_path.open("a", encoding="utf-8") as f:
                f.write(f"Testing {hex_file.name} Timeout\n")
            cleanup(temp_files)
            continue

        stdout_content = stdout_file.read_text(encoding="utf-8", errors="ignore")

        with result_path.open("a", encoding="utf-8") as f:
            f.write(f"{hex_file.stem.split('-')[-1]} \t & ")
            table_lines = [line for line in stdout_content.splitlines() if line and "\t" in line]
            if table_lines:
                result_line = table_lines[-1]
                results = parse_result_line(result_line)
                results_line = "\t & ".join(str(x) for x in results)
                f.write(f"{results_line} \t & ")
                if is_passed(result_line):
                    f.write(f"Passed\n")
                else:
                    f.write(f"Failed\n")
            else:
                f.write(f"Testing {hex_file.stem.split('-')[-1]} Failed\n")

        cleanup(temp_files)
        cleanup_autotest_files(script_dir)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
