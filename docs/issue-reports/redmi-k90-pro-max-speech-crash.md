# Redmi K90 Pro Max 语音识别 native crash

## 现象

在 Redmi K90 Pro Max 上使用语音识别时，App 发生 native crash。

设备/系统：

```text
Redmi/myron/myron:16/BP2A.250605.031.A3/OS3.0.303.0.WPMCNXM:user/release-keys
```

Crash 栈顶部集中在 `libonnxruntime.so`，随后进入 `libsherpa-onnx-c-api.so` 和 Flutter 侧调用链；同一 native crash 栈在日志中重复出现。

```text
#00 pc 0000000000766968  base.apk!libonnxruntime.so (offset 0x3274000) (BuildId: 43c64ac553541aa9efc66aea29478734a85ad091)
#01 pc 00000000011ae478  base.apk!libonnxruntime.so (offset 0x3274000)
...
#17 pc 00000000002cdfb8  base.apk!libsherpa-onnx-c-api.so (offset 0x44e8000) (BuildId: 94fadc65ccd7b5f1ed4e62e8975914b418bc4e7b)
#18 pc 00000000002cd254  base.apk!libsherpa-onnx-c-api.so (offset 0x44e8000)
#19 pc 00000000002cbab4  base.apk!libsherpa-onnx-c-api.so (offset 0x44e8000)
...
#34 pc 00000000008e755c  base.apk!libflutter.so (offset 0x1294000) (BuildId: d73e2148690c74c5118334d5bfdac1dd153b1cbb)
```

## 可能问题

语音识别的 `sherpa_onnx` / `onnxruntime` native 推理链路可能和该机型、Android 16 或 HyperOS 3 的运行环境存在兼容性问题，或在识别器初始化/推理时触发 ORT native 崩溃。需要进一步确认是模型加载、采样数据输入还是 CPU/线程/NNAPI 相关路径导致。

## 期望

在该机型上语音识别不应导致 App 进程崩溃；如果本地语音模型不可用，应降级为可恢复错误提示。
