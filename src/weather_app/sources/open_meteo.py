# -*- coding: utf-8 -*-
"""Open-Meteo：主预报（16 天）+ 7 天扩展（UV/能见度）+ 空气质量 + 多模型对比
文档：https://open-meteo.com/en/docs  免费、无需密钥"""
from .base import http_get

_BASE = "https://api.open-meteo.com/v1/forecast"
_AQ = "https://air-quality-api.open-meteo.com/v1/air-quality"


def forecast(lat: float, lon: float, tz: str, timeout: float = 20):
    """16 天主预报（不含 UV/能见度）"""
    params = {
        "latitude": lat, "longitude": lon, "timezone": tz or "auto",
        "forecast_days": 16,
        "current": ("temperature_2m,relative_humidity_2m,apparent_temperature,is_day,"
                    "precipitation,weather_code,wind_speed_10m,wind_direction_10m,"
                    "wind_gusts_10m,pressure_msl"),
        "hourly": ("temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,"
                   "weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,"
                   "pressure_msl,is_day,precipitation_probability"),
        "daily": ("weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,"
                  "precipitation_sum,precipitation_probability_max,uv_index_max,"
                  "snowfall_sum,rain_sum,"
                  "wind_speed_10m_max,wind_gusts_10m_max"),
        "models": "best_match",
    }
    return http_get(_BASE, params, timeout)


def forecast_uv(lat: float, lon: float, tz: str, timeout: float = 20):
    """7 天扩展：UV 指数、能见度（Open-Meteo 对这两项仅提供 7 天）"""
    params = {
        "latitude": lat, "longitude": lon, "timezone": tz or "auto",
        "forecast_days": 7,
        "hourly": "uv_index,visibility,is_day",
        "models": "best_match",
    }
    return http_get(_BASE, params, timeout)


def model_temp(lat: float, lon: float, tz: str, model: str, timeout: float = 15):
    """单模型当前温度，用于多源对比"""
    params = {
        "latitude": lat, "longitude": lon, "timezone": tz or "auto",
        "current": "temperature_2m,apparent_temperature,is_day,weather_code",
        "models": model,
    }
    return http_get(_BASE, params, timeout)


def air_quality(lat: float, lon: float, tz: str, timeout: float = 20):
    params = {
        "latitude": lat, "longitude": lon, "timezone": tz or "auto",
        "current": "us_aqi,european_aqi,pm2_5,pm10",
    }
    return http_get(_AQ, params, timeout)
