extends RefCounted
class_name CombatTimebase


# CombatLab 的逻辑帧基准。
# 运行时仍使用秒；编辑器与动画配置可通过此类转换为帧。
const PHYSICS_TICK_RATE: int = 60
const FRAME_DURATION: float = 1.0 / float(PHYSICS_TICK_RATE)


static func seconds_to_frames(seconds: float) -> int:
	return roundi(seconds * float(PHYSICS_TICK_RATE))


static func frames_to_seconds(frames: int) -> float:
	return float(frames) / float(PHYSICS_TICK_RATE)
