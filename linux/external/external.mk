# BR2_EXTERNAL for the GSAT MB86H615 headless Linux build.
# No out-of-tree packages yet; board support lives in board/gsat-mb86h615/.
include $(sort $(wildcard $(BR2_EXTERNAL_GSAT_PATH)/package/*/*.mk))
