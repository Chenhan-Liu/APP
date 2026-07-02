const weatherButton = document.querySelector("#weatherButton");
const result = document.querySelector("#result");
const message = document.querySelector("#message");
const temperature = document.querySelector("#temperature");
const apparentTemperature = document.querySelector("#apparentTemperature");
const humidity = document.querySelector("#humidity");
const precipitation = document.querySelector("#precipitation");
const windSpeed = document.querySelector("#windSpeed");
const weatherIcon = document.querySelector("#weatherIcon");
const weatherDescription = document.querySelector("#weatherDescription");
const country = document.querySelector("#country");
const city = document.querySelector("#city");
const updatedAt = document.querySelector("#updatedAt");

weatherButton.addEventListener("click", getCurrentWeather);

async function getCurrentWeather() {
  setLoading(true);
  showMessage("正在获取当前位置...", "success");

  try {
    const position = await getPosition();
    const { latitude, longitude } = position.coords;
    const weather = await fetchWeather(latitude, longitude);
    const location = await fetchLocationNameSafely(latitude, longitude);

    renderWeather(weather, location);
    showMessage("气温已更新。", "success");
  } catch (error) {
    result.hidden = true;
    showMessage(getFriendlyError(error));
  } finally {
    setLoading(false);
  }
}

function getPosition() {
  return new Promise((resolve, reject) => {
    if (!("geolocation" in navigator)) {
      reject(new Error("GEOLOCATION_UNSUPPORTED"));
      return;
    }

    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: true,
      timeout: 10000,
      maximumAge: 0,
    });
  });
}

async function fetchWeather(latitude, longitude) {
  const params = new URLSearchParams({
    latitude,
    longitude,
    current: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,wind_speed_10m,weather_code,is_day",
    timezone: "auto",
  });

  const response = await fetch(`https://api.open-meteo.com/v1/forecast?${params}`);

  if (!response.ok) {
    throw new Error("WEATHER_REQUEST_FAILED");
  }

  const data = await response.json();

  if (!data.current || typeof data.current.temperature_2m !== "number") {
    throw new Error("WEATHER_DATA_INVALID");
  }

  return data;
}

async function fetchLocationName(latitude, longitude) {
  const params = new URLSearchParams({
    latitude,
    longitude,
    localityLanguage: getPreferredLanguage(),
  });

  const response = await fetch(`https://api.bigdatacloud.net/data/reverse-geocode-client?${params}`);

  if (!response.ok) {
    throw new Error("LOCATION_REQUEST_FAILED");
  }

  const data = await response.json();

  if (!data.countryName && !data.city && !data.locality) {
    throw new Error("LOCATION_DATA_INVALID");
  }

  return data;
}

async function fetchLocationNameSafely(latitude, longitude) {
  try {
    return await fetchLocationName(latitude, longitude);
  } catch {
    return getDefaultLocation();
  }
}

function getDefaultLocation() {
  return {
    countryName: "",
    principalSubdivision: "",
    city: "",
    locality: "",
  };
}

function renderWeather(weather, location) {
  const unit = weather.current_units?.temperature_2m || "°C";
  const time = weather.current.time;
  const weatherInfo = getWeatherInfo(weather.current.weather_code, weather.current.is_day);

  setWeatherTheme(weatherInfo.theme);
  weatherIcon.textContent = weatherInfo.icon;
  weatherDescription.textContent = weatherInfo.text;
  temperature.textContent = `${weather.current.temperature_2m}${unit}`;
  apparentTemperature.textContent = formatWeatherValue(weather, "apparent_temperature", "°C");
  humidity.textContent = formatWeatherValue(weather, "relative_humidity_2m", "%");
  precipitation.textContent = formatWeatherValue(weather, "precipitation", "mm");
  windSpeed.textContent = formatWeatherValue(weather, "wind_speed_10m", "km/h");
  country.textContent = formatCountry(location);
  city.textContent = formatCity(location);
  updatedAt.textContent = formatDateTime(time);
  result.hidden = false;
}

function formatWeatherValue(weather, key, fallbackUnit) {
  const value = weather.current?.[key];

  if (typeof value !== "number") {
    return "--";
  }

  return `${value}${weather.current_units?.[key] || fallbackUnit}`;
}

function formatCountry(location) {
  return [location.countryName, location.principalSubdivision]
    .filter(Boolean)
    .join(" / ") || "暂未识别";
}

function formatCity(location) {
  return location.city || location.locality || "暂未识别";
}

function getPreferredLanguage() {
  return (navigator.language || "zh").split("-")[0];
}

function setWeatherTheme(theme) {
  const themes = ["sunny", "cloudy", "rainy", "snowy", "stormy"];
  document.body.classList.remove(...themes);
  document.body.classList.add(themes.includes(theme) ? theme : "cloudy");
}

function getWeatherInfo(code, isDay) {
  const weatherMap = {
    0: { day: "☀️", night: "🌙", text: "晴朗" },
    1: { day: "🌤️", night: "🌙", text: "大致晴朗" },
    2: { day: "⛅", night: "☁️", text: "局部多云" },
    3: { day: "☁️", night: "☁️", text: "阴天" },
    45: { day: "🌫️", night: "🌫️", text: "有雾" },
    48: { day: "🌫️", night: "🌫️", text: "雾凇" },
    51: { day: "🌦️", night: "🌧️", text: "小毛毛雨" },
    53: { day: "🌦️", night: "🌧️", text: "中等毛毛雨" },
    55: { day: "🌧️", night: "🌧️", text: "大毛毛雨" },
    56: { day: "🌧️", night: "🌧️", text: "冻毛毛雨" },
    57: { day: "🌧️", night: "🌧️", text: "强冻毛毛雨" },
    61: { day: "🌦️", night: "🌧️", text: "小雨" },
    63: { day: "🌧️", night: "🌧️", text: "中雨" },
    65: { day: "🌧️", night: "🌧️", text: "大雨" },
    66: { day: "🌧️", night: "🌧️", text: "冻雨" },
    67: { day: "🌧️", night: "🌧️", text: "强冻雨" },
    71: { day: "🌨️", night: "🌨️", text: "小雪" },
    73: { day: "🌨️", night: "🌨️", text: "中雪" },
    75: { day: "❄️", night: "❄️", text: "大雪" },
    77: { day: "🌨️", night: "🌨️", text: "雪粒" },
    80: { day: "🌦️", night: "🌧️", text: "小阵雨" },
    81: { day: "🌧️", night: "🌧️", text: "中等阵雨" },
    82: { day: "⛈️", night: "⛈️", text: "强阵雨" },
    85: { day: "🌨️", night: "🌨️", text: "小阵雪" },
    86: { day: "❄️", night: "❄️", text: "强阵雪" },
    95: { day: "⛈️", night: "⛈️", text: "雷暴" },
    96: { day: "⛈️", night: "⛈️", text: "雷暴伴小冰雹" },
    99: { day: "⛈️", night: "⛈️", text: "雷暴伴强冰雹" },
  };

  const fallback = { day: "🌡️", night: "🌡️", text: "未知天气" };
  const weather = weatherMap[code] || fallback;

  return {
    icon: isDay === 0 ? weather.night : weather.day,
    text: weather.text,
    description: weather.text,
    theme: getWeatherTheme(code),
  };
}

function getWeatherTheme(code) {
  const themeMap = {
    sunny: [0, 1],
    cloudy: [2, 3, 45, 48],
    rainy: [51, 53, 55, 61, 63, 65, 80, 81, 82],
    snowy: [56, 57, 66, 67, 71, 73, 75, 77, 85, 86],
    stormy: [95, 96, 99],
  };

  return Object.keys(themeMap).find((theme) => themeMap[theme].includes(code)) || "cloudy";
}

function formatDateTime(value) {
  if (!value) {
    return "暂无时间";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("zh-CN", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function setLoading(isLoading) {
  weatherButton.disabled = isLoading;
  weatherButton.textContent = isLoading ? "正在获取..." : "获取当前位置气温";
}

function showMessage(text, type = "error") {
  message.textContent = text;
  message.className = `message ${type === "success" ? "success" : ""}`;
}

function getFriendlyError(error) {
  if (error.code === 1) {
    return "无法获取定位权限。你可以在浏览器设置中允许定位后再试一次。";
  }

  if (error.code === 2) {
    return "暂时无法确定你的位置，请稍后再试。";
  }

  if (error.code === 3) {
    return "定位请求超时了，请确认网络或定位服务可用后再试。";
  }

  if (error.message === "GEOLOCATION_UNSUPPORTED") {
    return "当前浏览器不支持定位功能，请换用现代浏览器访问。";
  }

  if (error.message === "LOCATION_REQUEST_FAILED" || error.message === "LOCATION_DATA_INVALID") {
    return "位置名称获取失败，请稍后再试。";
  }

  return "天气数据获取失败，请稍后再试。";
}
