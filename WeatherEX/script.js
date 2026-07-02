const weatherButton = document.querySelector("#weatherButton");
const result = document.querySelector("#result");
const message = document.querySelector("#message");
const temperature = document.querySelector("#temperature");
const latitudeText = document.querySelector("#latitude");
const longitudeText = document.querySelector("#longitude");
const updatedAt = document.querySelector("#updatedAt");

weatherButton.addEventListener("click", getCurrentWeather);

async function getCurrentWeather() {
  setLoading(true);
  showMessage("正在获取当前位置...", "success");

  try {
    const position = await getPosition();
    const { latitude, longitude } = position.coords;
    const weather = await fetchWeather(latitude, longitude);

    renderWeather(latitude, longitude, weather);
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
    current: "temperature_2m",
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

function renderWeather(latitude, longitude, weather) {
  const unit = weather.current_units?.temperature_2m || "°C";
  const time = weather.current.time;

  temperature.textContent = `${weather.current.temperature_2m}${unit}`;
  latitudeText.textContent = latitude.toFixed(5);
  longitudeText.textContent = longitude.toFixed(5);
  updatedAt.textContent = formatDateTime(time);
  result.hidden = false;
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

  return "天气数据获取失败，请稍后再试。";
}
