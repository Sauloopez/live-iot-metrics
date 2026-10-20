import {
  Chart,
  LineController,
  LineElement,
  PointElement,
  LinearScale,
  Filler,
  Tooltip,
} from "chart.js";

// Register only what a live line chart needs to keep the bundle small
Chart.register(LineController, LineElement, PointElement, LinearScale, Filler, Tooltip);

const MAX_POINTS = 50;

// Times and numbers match the server-rendered header and table: UTC, 24h, dot decimals
const timeFormat = new Intl.DateTimeFormat("en-GB", {
  hour: "2-digit",
  minute: "2-digit",
  timeZone: "UTC",
});

const secondsTimeFormat = new Intl.DateTimeFormat("en-GB", {
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  timeZone: "UTC",
});

// Short windows (fast sensors) need seconds on the axis, otherwise every tick reads the same
const SHORT_SPAN_MS = 3 * 60 * 1000;

const fullTimeFormat = new Intl.DateTimeFormat("en-GB", {
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  timeZone: "UTC",
});

// Ticks drop trailing zeros; readings always show two decimals like the header
const formatTick = (value) => (Number.isFinite(value) ? String(Number(value.toFixed(2))) : "-");
const formatValue = (value) => (Number.isFinite(value) ? value.toFixed(2) : "-");

const parseNumber = (raw) => {
  const n = parseFloat(raw);
  return Number.isFinite(n) ? n : null;
};

const withAlpha = (hex, alpha) => {
  const h = hex.trim().replace("#", "");
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
};

// Shades the target range behind the line so readers see at a glance whether readings sit inside it
const rangeBandPlugin = {
  id: "rangeBand",
  beforeDatasetsDraw(chart, _args, opts) {
    const { min, max, color } = opts;
    if (min == null || max == null) return;

    const { ctx, chartArea, scales } = chart;
    const top = Math.max(scales.y.getPixelForValue(max), chartArea.top);
    const bottom = Math.min(scales.y.getPixelForValue(min), chartArea.bottom);
    if (bottom <= top) return;

    ctx.save();
    ctx.fillStyle = withAlpha(color, 0.08);
    ctx.fillRect(chartArea.left, top, chartArea.right - chartArea.left, bottom - top);

    ctx.strokeStyle = withAlpha(color, 0.45);
    ctx.lineWidth = 1;
    ctx.beginPath();
    [top, bottom].forEach((y) => {
      ctx.moveTo(chartArea.left, Math.round(y) + 0.5);
      ctx.lineTo(chartArea.right, Math.round(y) + 0.5);
    });
    ctx.stroke();
    ctx.restore();
  },
};

// Vertical hairline that snaps to the hovered reading
const crosshairPlugin = {
  id: "crosshair",
  afterDatasetsDraw(chart, _args, opts) {
    const active = chart.tooltip?.getActiveElements?.() || [];
    if (!active.length) return;

    const { ctx, chartArea } = chart;
    const x = Math.round(active[0].element.x) + 0.5;

    ctx.save();
    ctx.strokeStyle = opts.color;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x, chartArea.top);
    ctx.lineTo(x, chartArea.bottom);
    ctx.stroke();
    ctx.restore();
  },
};

export const ChartHook = {
  mounted() {
    this.chartId = this.el.dataset.chartId;
    this.label = this.el.dataset.label || "";
    this.readRange();

    const readings = JSON.parse(this.el.dataset.readings || "[]");
    this.points = readings
      .map((r) => ({ x: new Date(r.time).getTime(), y: r.value }))
      .filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y))
      .sort((a, b) => a.x - b.x);

    this.canvas = document.createElement("canvas");
    this.canvas.setAttribute("role", "img");
    this.el.appendChild(this.canvas);

    this.colors = this.readColors();
    this.chart = new Chart(this.canvas, this.buildConfig());
    this.describe();

    this.handleEvent("new-data", (payload) => {
      // The same sensor may have several charts on the page; the server targets one
      if (payload.chart_id !== this.chartId) return;

      const point = { x: new Date(payload.time).getTime(), y: payload.value };
      if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) return;

      this.insertPoint(point);
      if (this.points.length > MAX_POINTS) this.points.shift();

      // No animation for live data: shifting the window would make every point tween
      // from its neighbour's old position and the whole line would jump
      this.chart.update("none");
      this.describe();
    });

    // Re-read the chart tokens whenever the theme toggle or the OS preference changes
    this.themeObserver = new MutationObserver(() => this.applyTheme());
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    });
    this.colorScheme = window.matchMedia("(prefers-color-scheme: dark)");
    this.onSchemeChange = () => this.applyTheme();
    this.colorScheme.addEventListener("change", this.onSchemeChange);
  },

  // phx-update="ignore" still patches the container attributes, so a range edit lands here
  updated() {
    this.readRange();
    this.chart.options.plugins.rangeBand.min = this.min;
    this.chart.options.plugins.rangeBand.max = this.max;
    this.chart.options.scales.y.suggestedMin = this.min ?? undefined;
    this.chart.options.scales.y.suggestedMax = this.max ?? undefined;
    this.chart.update("none");
  },

  destroyed() {
    this.themeObserver?.disconnect();
    this.colorScheme?.removeEventListener("change", this.onSchemeChange);
    this.chart?.destroy();
  },

  // Readings can arrive out of order; keep points sorted by time so the line never loops back
  insertPoint(point) {
    let i = this.points.length;
    while (i > 0 && this.points[i - 1].x > point.x) i--;
    if (i > 0 && this.points[i - 1].x === point.x) {
      this.points[i - 1] = point;
    } else {
      this.points.splice(i, 0, point);
    }
  },

  readRange() {
    this.min = parseNumber(this.el.dataset.min);
    this.max = parseNumber(this.el.dataset.max);
  },

  readColors() {
    const style = getComputedStyle(this.el);
    const token = (name) => style.getPropertyValue(name).trim();

    return {
      surface: token("--viz-surface"),
      ink: token("--viz-ink"),
      inkSecondary: token("--viz-ink-secondary"),
      muted: token("--viz-muted"),
      grid: token("--viz-grid"),
      baseline: token("--viz-baseline"),
      series: token("--viz-series"),
      good: token("--viz-good"),
      critical: token("--viz-critical"),
      ring: token("--viz-ring"),
    };
  },

  applyTheme() {
    this.colors = this.readColors();
    const config = this.buildConfig();
    this.chart.options = config.options;
    this.chart.data.datasets[0] = { ...config.data.datasets[0], data: this.points };
    this.chart.update("none");
  },

  outOfRange(value) {
    return (this.min != null && value < this.min) || (this.max != null && value > this.max);
  },

  // Accessible summary for screen readers; the table view under the chart holds every value
  describe() {
    const last = this.points[this.points.length - 1];
    const range =
      this.min != null && this.max != null
        ? `, target range ${formatTick(this.min)} to ${formatTick(this.max)}`
        : "";
    const latest = last ? `, latest ${formatValue(last.y)}` : ", no readings yet";
    this.canvas.setAttribute(
      "aria-label",
      `${this.label} measurements over time${range}${latest}`,
    );
  },

  buildConfig() {
    const c = this.colors;
    const hook = this;
    const isLast = (ctx) => ctx.dataIndex === hook.points.length - 1;
    const flagged = (ctx) => hook.outOfRange(ctx.raw?.y);
    // Mark where an excursion starts or ends (and isolated spikes) instead of every
    // out-of-range reading; the red segments already show the whole excursion
    const excursionEdge = (ctx) => {
      if (!flagged(ctx)) return false;
      const prev = hook.points[ctx.dataIndex - 1];
      const next = hook.points[ctx.dataIndex + 1];
      return (prev && !hook.outOfRange(prev.y)) || (next && !hook.outOfRange(next.y));
    };

    return {
      type: "line",
      data: {
        datasets: [
          {
            label: this.label,
            data: this.points,
            borderColor: c.series,
            borderWidth: 2,
            borderJoinStyle: "round",
            borderCapStyle: "round",
            cubicInterpolationMode: "monotone",
            // Segments leaving the target range switch to the critical color
            segment: {
              borderColor: (ctx) =>
                hook.outOfRange(ctx.p0.parsed.y) || hook.outOfRange(ctx.p1.parsed.y)
                  ? c.critical
                  : c.series,
            },
            fill: "start",
            backgroundColor: (ctx) => {
              const area = ctx.chart.chartArea;
              if (!area) return withAlpha(c.series, 0.1);
              const gradient = ctx.chart.ctx.createLinearGradient(0, area.top, 0, area.bottom);
              gradient.addColorStop(0, withAlpha(c.series, 0.18));
              gradient.addColorStop(1, withAlpha(c.series, 0));
              return gradient;
            },
            // Points only where they carry meaning: out-of-range readings and the live tip
            pointRadius: (ctx) => (excursionEdge(ctx) || isLast(ctx) ? 4 : 0),
            pointHoverRadius: 6,
            pointHitRadius: 12,
            pointBackgroundColor: (ctx) => (flagged(ctx) ? c.critical : c.series),
            pointHoverBackgroundColor: (ctx) => (flagged(ctx) ? c.critical : c.series),
            pointBorderColor: c.surface,
            pointHoverBorderColor: c.surface,
            pointBorderWidth: 2,
            pointHoverBorderWidth: 2,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        parsing: false,
        normalized: true,
        animation: { duration: 350, easing: "easeOutCubic" },
        interaction: { mode: "nearest", axis: "x", intersect: false },
        layout: { padding: { top: 8, right: 8 } },
        scales: {
          x: {
            type: "linear",
            bounds: "data",
            border: { color: c.baseline },
            grid: { display: false },
            ticks: {
              color: c.muted,
              font: { size: 11 },
              maxTicksLimit: 6,
              maxRotation: 0,
              callback(value) {
                const format = this.max - this.min < SHORT_SPAN_MS ? secondsTimeFormat : timeFormat;
                return format.format(new Date(value));
              },
            },
          },
          y: {
            suggestedMin: this.min ?? undefined,
            suggestedMax: this.max ?? undefined,
            // 5% breathing room, but never push a non-negative series below zero
            afterDataLimits(scale) {
              const pad = (scale.max - scale.min) * 0.05 || 1;
              scale.max += pad;
              scale.min = scale.min >= 0 ? Math.max(0, scale.min - pad) : scale.min - pad;
            },
            border: { display: false },
            grid: { color: c.grid, lineWidth: 1, drawTicks: false },
            ticks: {
              color: c.muted,
              font: { size: 11 },
              padding: 8,
              maxTicksLimit: 5,
              callback: (value) => formatTick(value),
            },
          },
        },
        plugins: {
          legend: { display: false },
          rangeBand: { min: this.min, max: this.max, color: c.good },
          crosshair: { color: c.baseline },
          tooltip: {
            backgroundColor: c.surface,
            borderColor: c.ring,
            borderWidth: 1,
            titleColor: c.ink,
            bodyColor: c.inkSecondary,
            titleFont: { size: 14, weight: "bold" },
            bodyFont: { size: 12 },
            padding: 10,
            cornerRadius: 8,
            displayColors: false,
            caretSize: 0,
            // Value leads, context follows
            callbacks: {
              title: (items) => formatValue(items[0].raw.y),
              label: (item) => {
                const lines = [fullTimeFormat.format(new Date(item.raw.x))];
                if (hook.min != null && hook.max != null) {
                  lines.push(hook.outOfRange(item.raw.y) ? "⚠ Out of range" : "✓ In range");
                }
                return lines;
              },
            },
          },
        },
      },
      plugins: [rangeBandPlugin, crosshairPlugin],
    };
  },
};
