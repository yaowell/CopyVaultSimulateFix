TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CopyVaultSimulateFix

CopyVaultSimulateFix_FILES = CVSimulateFix.m
CopyVaultSimulateFix_CFLAGS = -fobjc-arc

# 解决新版 Xcode 传参导致的 clang 报错和段错误
ADDITIONAL_CFLAGS = -Wno-error=unused-command-line-argument

include $(THEOS_MAKE_PATH)/tweak.mk
