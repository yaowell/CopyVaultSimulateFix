TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CopyVaultSimulateFix

CopyVaultSimulateFix_FILES = CVSimulateFix.m
CopyVaultSimulateFix_CFLAGS = -fobjc-arc

# 显式链接 substrate 库，解决 _MSHookMessageEx 找不到符号的问题
CopyVaultSimulateFix_LIBRARIES = substrate

# 过滤新版 Xcode 工具链参数警告
ADDITIONAL_CFLAGS = -Wno-error=unused-command-line-argument

include $(THEOS_MAKE_PATH)/tweak.mk
