/**
 * Country page — Plotly-based interactive trajectories.
 * Plotly gives us zoom, pan, hover tooltips, legend click-toggle for free.
 *
 * Custom controls (rebuild on change):
 *   X / Y axis dropdowns  |  ⇄ swap axes  |  last-N elections  |  all-elections
 *
 * Each plot_data row = one party-year manifesto with fields:
 *   doc_id, year, party, partyabbrev, partyname, label,
 *   populism_overall, liberalism_overall, pop_ideology_overall
 */
window.renderCountryPlots = async function (tsId, scId, plotData, countryName) {
  // Lazy-load Plotly from CDN (one load per browser session, cached after)
  if (!window.Plotly) {
    await new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = "https://cdn.plot.ly/plotly-2.35.2.min.js";
      s.onload = resolve; s.onerror = reject;
      document.head.appendChild(s);
    });
  }
  const Plotly = window.Plotly;

  // ---------- Dimension catalogue ----------
  const DIMS = {
    populism_overall:     "Populism (overall)",
    pop_ideology_overall: "Ideology (Right − Left)",
    liberalism_overall:   "Liberalism (overall)",
    lib_political:        "Liberalism — Political",
    lib_social:           "Liberalism — Social",
    lib_economic:         "Liberalism — Economic",
    lib_financial_market: "Liberalism — Financial-market"
  };

  // ---------- Party colour map ----------
  const allParties = [...new Set(plotData.map(d => d.label))].sort();
  const palette = [
    "#1f77b4","#ff7f0e","#2ca02c","#d62728","#9467bd",
    "#8c564b","#e377c2","#7f7f7f","#bcbd22","#17becf",
    "#aec7e8","#ffbb78","#98df8a","#ff9896","#c5b0d5",
    "#c49c94","#f7b6d2","#c7c7c7","#dbdb8d","#9edae5"
  ];
  const colourFor = p => palette[allParties.indexOf(p) % palette.length];

  // ---------- State (only x/y and time-window — Plotly's legend handles party toggling) ----------
  const state = {
    xDim: "populism_overall",
    yDim: "liberalism_overall",
    nLastElections: 4
  };

  // ---------- Build top control bar ----------
  function buildControls(host) {
    host.innerHTML = `
      <div style="display:flex; gap:1.2rem; flex-wrap:wrap; margin-bottom:.6rem; align-items:flex-end">
        <label>X-axis
          <select id="x-dim" style="margin-left:.3rem">${
            Object.entries(DIMS).map(([k,v]) =>
              `<option value="${k}" ${k===state.xDim?'selected':''}>${v}</option>`).join("")
          }</select>
        </label>
        <label>Y-axis
          <select id="y-dim" style="margin-left:.3rem">${
            Object.entries(DIMS).map(([k,v]) =>
              `<option value="${k}" ${k===state.yDim?'selected':''}>${v}</option>`).join("")
          }</select>
        </label>
        <button id="swap-axes" style="padding:.2rem .6rem">⇄ Swap axes</button>
        <label>Last
          <input type="number" id="n-last" value="${state.nLastElections}" min="1" max="30" step="1" style="width:3.5em;margin:0 .3rem">
          elections per party
        </label>
        <button id="all-time" style="padding:.2rem .6rem">All elections</button>
        <span style="font-size:.85em;color:#666;margin-left:auto">
          Click a party in the legend to toggle.  Double-click to isolate.
        </span>
      </div>`;
  }

  // ---------- Filter: keep only manifestos from the last N COUNTRY-WIDE elections ----------
  function filterData() {
    if (!state.nLastElections) return plotData;
    // Group election years into "election waves". Different parties may have
    // off-by-a-month dates around the same election; bucket years within ±1 of
    // a peak so e.g. 2017+2018 in one country read as one election wave.
    const years = [...new Set(plotData.map(d => d.year))].sort((a,b) => a - b);
    const waves = [];
    for (const y of years) {
      if (waves.length && y - waves[waves.length-1].max <= 1) {
        waves[waves.length-1].max = y;
        waves[waves.length-1].years.add(y);
      } else {
        waves.push({ max: y, years: new Set([y]) });
      }
    }
    // Take the last N waves and collect their years into a Set
    const lastWaves = waves.slice(-state.nLastElections);
    const keepYears = new Set();
    for (const w of lastWaves) for (const y of w.years) keepYears.add(y);
    return plotData.filter(d => keepYears.has(d.year));
  }

  // ---------- Group data by party ----------
  function groupByParty(data) {
    const byParty = new Map();
    for (const d of data) {
      if (!byParty.has(d.label)) byParty.set(d.label, []);
      byParty.get(d.label).push(d);
    }
    for (const [p, rows] of byParty) rows.sort((a, b) => a.year - b.year);
    return byParty;
  }

  // ---------- Time-series plot (2 stacked panels) ----------
  function renderTS(host, data) {
    const byParty = groupByParty(data);
    const traces = [];
    for (const [p, rows] of byParty) {
      const c = colourFor(p);
      traces.push({
        type: "scatter", mode: "lines+markers",
        name: p, legendgroup: p,
        x: rows.map(r => r.year),
        y: rows.map(r => r[state.xDim]),
        xaxis: "x1", yaxis: "y1",
        line: { color: c, width: 2 },
        marker: { color: c, size: 7 },
        hovertemplate: `<b>${p}</b><br>%{x}<br>${DIMS[state.xDim]}: %{y:.2f}<extra></extra>`,
        showlegend: true
      });
      traces.push({
        type: "scatter", mode: "lines+markers",
        name: p, legendgroup: p,
        x: rows.map(r => r.year),
        y: rows.map(r => r[state.yDim]),
        xaxis: "x2", yaxis: "y2",
        line: { color: c, width: 2 },
        marker: { color: c, size: 7 },
        hovertemplate: `<b>${p}</b><br>%{x}<br>${DIMS[state.yDim]}: %{y:.2f}<extra></extra>`,
        showlegend: false
      });
    }
    const layout = {
      grid: { rows: 2, columns: 1, pattern: "independent", roworder: "top to bottom" },
      xaxis:  { domain: [0, 1], anchor: "y1", title: "" },
      yaxis:  { domain: [0.55, 1], anchor: "x1", title: DIMS[state.xDim], range: [0, 10] },
      xaxis2: { domain: [0, 1], anchor: "y2", title: "Election year" },
      yaxis2: { domain: [0, 0.45], anchor: "x2", title: DIMS[state.yDim], range: [0, 10] },
      margin: { t: 30, l: 60, r: 20, b: 50 },
      height: 600,
      legend: { orientation: "v", x: 1.02, y: 1 },
      hovermode: "closest"
    };
    Plotly.newPlot(host, traces, layout, {
      responsive: true, displaylogo: false,
      modeBarButtonsToRemove: ["lasso2d", "select2d"]
    });
  }

  // ---------- Scatter / trajectory plot ----------
  function renderScatter(host, data) {
    const byParty = groupByParty(data);
    const traces = [];
    const annotations = [
      // Faint quadrant lines via shapes
    ];
    const shapes = [
      { type: "line", x0: 5, x1: 5, y0: 0, y1: 10,
        line: { color: "#ccc", dash: "dot", width: 1 } },
      { type: "line", x0: 0, x1: 10, y0: 5, y1: 5,
        line: { color: "#ccc", dash: "dot", width: 1 } }
    ];

    for (const [p, rows] of byParty) {
      const c = colourFor(p);
      const xs = rows.map(r => r[state.xDim]);
      const ys = rows.map(r => r[state.yDim]);
      const yrs = rows.map(r => r.year);
      const n = rows.length;

      // Main trace: connected line + markers
      traces.push({
        type: "scatter", mode: "lines+markers+text",
        name: p, legendgroup: p,
        x: xs, y: ys,
        text: yrs.map(String),
        textposition: "top center",
        textfont: { size: 9, color: "#444" },
        line: { color: c, width: 2 },
        marker: { color: c, size: 7, line: { color: "white", width: 1 } },
        hovertemplate: `<b>${p}</b> %{text}<br>` +
                       `${DIMS[state.xDim]}: %{x:.2f}<br>` +
                       `${DIMS[state.yDim]}: %{y:.2f}<extra></extra>`,
        showlegend: true
      });

      // Big marker on the most-recent point (last in sorted rows)
      traces.push({
        type: "scatter", mode: "markers+text",
        name: p + " (latest)", legendgroup: p,
        x: [xs[n-1]], y: [ys[n-1]],
        text: [p],
        textposition: "middle right",
        textfont: { size: 11, color: c, weight: "bold" },
        marker: { color: c, size: 14, line: { color: "black", width: 1.3 } },
        hovertemplate: `<b>${p}</b> ${yrs[n-1]} (latest)<br>` +
                       `${DIMS[state.xDim]}: %{x:.2f}<br>` +
                       `${DIMS[state.yDim]}: %{y:.2f}<extra></extra>`,
        showlegend: false
      });

      // Arrow annotations between consecutive points (oldest → newest)
      for (let i = 0; i < n - 1; i++) {
        annotations.push({
          x: xs[i+1], y: ys[i+1],
          ax: xs[i],  ay: ys[i],
          xref: "x", yref: "y", axref: "x", ayref: "y",
          showarrow: true,
          arrowhead: 3, arrowsize: 1.2, arrowwidth: 1.2,
          arrowcolor: c,
          opacity: 0.55,
          standoff: 6, startstandoff: 6
        });
      }
    }

    const layout = {
      title: { text: "", font: { size: 14 } },
      xaxis: { title: DIMS[state.xDim] + " →", range: [0, 10], gridcolor: "#eee" },
      yaxis: { title: "↑ " + DIMS[state.yDim], range: [0, 10], gridcolor: "#eee" },
      annotations: annotations,
      shapes: shapes,
      margin: { t: 30, l: 60, r: 20, b: 50 },
      height: 620,
      legend: { orientation: "v", x: 1.02, y: 1 },
      hovermode: "closest"
    };
    Plotly.newPlot(host, traces, layout, {
      responsive: true, displaylogo: false,
      modeBarButtonsToRemove: ["lasso2d", "select2d"]
    });
  }

  // ---------- Wire up everything ----------
  const tsHost = document.getElementById(tsId);
  const scHost = document.getElementById(scId);
  if (!tsHost || !scHost) {
    console.error("Country plots: missing target containers", tsId, scId);
    return;
  }
  const ctrls = document.createElement("div");
  ctrls.id = "country-ctrls";
  tsHost.parentNode.insertBefore(ctrls, tsHost);
  buildControls(ctrls);

  function refresh() {
    const data = filterData();
    if (data.length === 0) {
      tsHost.innerHTML = scHost.innerHTML =
        '<p style="color:#888"><em>No data in the selected window.</em></p>';
      return;
    }
    renderTS(tsHost, data);
    renderScatter(scHost, data);
  }

  ctrls.querySelector("#x-dim").addEventListener("change", e => { state.xDim = e.target.value; refresh(); });
  ctrls.querySelector("#y-dim").addEventListener("change", e => { state.yDim = e.target.value; refresh(); });
  ctrls.querySelector("#swap-axes").addEventListener("click", () => {
    [state.xDim, state.yDim] = [state.yDim, state.xDim];
    ctrls.querySelector("#x-dim").value = state.xDim;
    ctrls.querySelector("#y-dim").value = state.yDim;
    refresh();
  });
  ctrls.querySelector("#n-last").addEventListener("change", e => {
    state.nLastElections = Math.max(1, parseInt(e.target.value || "4", 10));
    refresh();
  });
  ctrls.querySelector("#all-time").addEventListener("click", () => {
    state.nLastElections = 0;
    ctrls.querySelector("#n-last").value = "";
    refresh();
  });

  refresh();
};
