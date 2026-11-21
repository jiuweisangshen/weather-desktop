# -*- coding: utf-8 -*-
"""本地 JSON 缓存，避免频繁刷新"""
import os
import json
import time

from . import config


class Cache:
    def __init__(self, cfg: dict):
        self.dir = config.cache_dir()
        self.ttl = int(cfg.get("cache_minutes", 20)) * 60

    def _path(self, key: str) -> str:
        safe = "".join(c if c.isalnum() else "_" for c in key)[:80]
        return os.path.join(self.dir, f"{safe}.json")

    def get(self, key: str, allow_stale: bool = False):
        p = self._path(key)
        if not os.path.exists(p):
            return None
        try:
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
            age = time.time() - data.get("_ts", 0)
            stale = age > self.ttl
            # 启动时允许先用过期缓存上屏（秒开），后台线程会再拉新数据覆盖
            if stale and not allow_stale:
                return None
            if not isinstance(data.get("meta"), dict):
                data["meta"] = {}
            data["meta"]["cache_hit"] = True
            data["meta"]["cache_stale"] = stale
            data["meta"]["cache_age_min"] = max(0, int(age // 60))
            return data
        except Exception:
            return None

    def set(self, key: str, payload: dict):
        tmp = None
        try:
            payload["_ts"] = time.time()
            p = self._path(key)
            tmp = p + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False)
            os.replace(tmp, p)
        except Exception:
            try:
                if tmp and os.path.exists(tmp):
                    os.remove(tmp)
            except Exception:
                pass

    def remove(self, key: str):
        """删除某条缓存（城市变化后清掉自动定位的旧缓存）"""
        try:
            p = self._path(key)
            if os.path.exists(p):
                os.remove(p)
        except Exception:
            pass
