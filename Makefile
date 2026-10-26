TARGET := iphone:clang:latest:14.0
ARCHS = iphoneos-arm64 iphoneos-arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CopyVaultSimulateFix

CopyVaultSimulateFix_FILES = CVSimulateFix.m
CopyVaultSimulateFix_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
