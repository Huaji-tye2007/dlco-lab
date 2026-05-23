# ABOUT THIS LAB

这个实验需要手动设计的其实只有两个实验：控制器和单周期CPU的设计，另外的实验都是在进行测试，`testcase`和`C Test`都是测试文件夹，内部包含测试文件。
考虑到需要测试的指令和程序众多，我编写了一个自动化测试脚本`autotest.sh`(适用于bash)和 ~~又臭又长的~~ `autotest.ps1`(适用于pwsh7，由copilot生成)。但是由于无法直接从circ文件修改RAM的值，而Logisim的命令行工具也无法单独修改RAM的值，因此`C Test`中的所有测试还是没有很好的办法实现自动化。

## ABOUT autotest

参考链接：

- [Logisim-ITA的命令行工具](https://cburch.com/logisim/docs/2.6.0/en/guide/verify/index.html)
- [一篇博客](https://foreveryolo.top/posts/6588/index.html)

### REQUIREMENTS

- Bash shell (for `autotest.sh`)
- PowerShell 7 (for `autotest.ps1`)
- **Logisim-ITA.jar** (for running the tests) **注意是jar文件！**
- 目录树：
    ```
    lab6
    ├── autotest.sh
    ├── autotest.ps1
    ├── Logisim-ITA.jar
    ├── lab6.5.circ # 仓库提供的测试电路图文件
    ├── testcase  # 课程提供的测试文件夹，不需要手动编译
    │   ├── rv32ui-p-add.hex
    │   ├── rv32ui-p-addi.hex
    │   ├── ...
    ```

### USAGE

首先，你需要对你的电路图进行一些修改，使其能够适配自动化测试脚本。具体的修改方案在实验报告中有写，这里不再赘述。需要将修改后的电路图保存为`lab6.5.circ`（这是在脚本中硬编码的），并放在与`autotest.sh`和`autotest.ps1`同一目录下。

然后在终端中输入如下命令：

```bash
# 进入lab6目录
cd path/to/lab6
# 对于bash用户
./autotest.sh
# 对于PowerShell用户
.\autotest.ps1
```

脚本会自动运行`lab6.5.circ`中的test电路图，并依次用`testcase`文件夹中的测试文件替换原有指令存储器的值进行测试。

测试结果输出在`result.txt`中格式如下：

```txt
<测试文件名> : <32位x10寄存器的值> <32位x3寄存器的值> <32位x1寄存器的值> <1位测试是否通过的标志位> <16位cycle值>
```

例如：

```txt
rv32ui-p-add.hex : 0000 0000 1100 0000 1111 1111 1110 1110  0000 0000 0000 0000 0000 0000 0010 0110  0000 0000 0000 0000 0000 0000 0001 0000 1 0000 0001 1100 1010
rv32ui-p-addi.hex : 0000 0000 1100 0000 1111 1111 1110 1110 0000 0000 0000 0000 0000 0000 0001 1001 0000 0000 0000 0000 0000 0000 0010 0001 1 0000 0000 1110 1011
```

如果测试没有通过，标志位是0，否则为1；并设置了100秒最大测试时间，如果显示`Testing xxx.hex Timeout`，说明测试没有在100秒内完成，大概率是电路设计有问题导致死循环。

Logisim-ITA的命令行工具在Windows下运行速度可能较慢，建议在Linux环境下运行测试脚本，或者使用WSL（Windows Subsystem for Linux）来运行测试脚本。

其实这部分的测试都不需要手动加载DataRAM的值，因为提供了不需要RAM的测试文件，而且产生的结果（指寄存器的值）应该是相同的（前提是DataRAM的实现绝对正确）。
