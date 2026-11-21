# -*- coding: utf-8 -*-
"""数据源公共请求工具"""
import requests


def http_get(url: str, params=None, timeout: float = 12, headers=None):
    r = requests.get(url, params=params, timeout=timeout, headers=headers or {})
    r.raise_for_status()
    return r.json()
