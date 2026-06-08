/**
 * Country page — interactive trajectories.
 * Controls (rebuilds plots on change):
 *   - Party checkboxes (toggle on/off; default: all selected)
 *   - X / Y axis dropdowns (any combination of overall dims)
 *   - Time window: how many most-recent elections to include per party (default 4)
 *
 * Time highlight: each trajectory uses per-segment colour gradient
 *   (older = pale, latest = saturated) plus small year labels.
 *
 * Each plot_data row = one party-year manifesto with fields:
 *   doc_id, year, party, partyabbrev, partyname, label,
 *   populism_overall, liberalism_overall, pop_ideology_overall
 */
window.renderCountryPlots = async function (tsId, scId, plotData, countryName) {
  const Plot = await import("https://cdn.jsdelivr.net/npm/@observablehq/plot@0.6/+esm");
  const d3   = await import("https://cdn.jsdelivr.net/npm/d3@7/+esm");

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

  // ---------- State ----------
  const state = {
    activeParties: new Set(allParties),
    xDim: "populism_overall",
    yDim: "liberalism_overall",
    nLastElections: 4
  };

  // ---------- Build UI controls ----------
  function buildControls(host) {
    host.innerHTML = `
      <div class="ctrls-row" style="display:flex; gap:1.2rem; flex-wrap:wrap; margin-bottom:.6rem; align-items:flex-end">
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
      </div>
      <div class="party-toggles" style="display:flex; flex-wrap:wrap; gap:.35rem .8rem; padding:.5rem .8rem; background:#fafafa; border-radius:4px; margin-bottom:.8rem">
        <strong style="margin-right:.3rem">Parties:</strong>
        <button id="select-all" style="padding:.05rem .5rem;font-size:.85em">all</button>
        <button id="select-none" style="padding:.05rem .5rem;font-size:.85em">none</button>
        ${allParties.map(p =>
          `<label style="display:flex;align-items:center;gap:.2rem;font-size:.9em">
             <input type="checkbox" data-party="${p}" checked
                    style="accent-color:${colourFor(p)};margin:0">
             <span style="color:${colourFor(p)};font-weight:600">${p}</span>
           </label>`
        ).join("")}
      </div>`;
  }

  // ---------- Filter helper ----------
  function filterData() {
    const dataByParty = new Map();
    for (const d of plotData) {
      if (!state.activeParties.has(d.label)) continue;
      if (!dataByParty.has(d.label)) dataByParty.set(d.label, []);
      dataByParty.get(d.label).push(d);
    }
    // Last N elections per party (or all if state.nLastElections is null/0)
    const out = [];
    for (const [p, rows] of dataByParty) {
      rows.sort((a, b) => a.year - b.year);
      const slice = state.nLastElections > 0 ? rows.slice(-state.nLastElections) : rows;
      out.push(...slice);
    }
    return out;
  }

  // ---------- Make per-segment data for gradient trajectories ----------
  function makeSegments(data) {
    // For each party, produce consecutive (year_i → year_{i+1}) segments
    const segs = [];
    const byParty = new Map();
    for (const d of data) {
      if (!byParty.has(d.label)) byParty.set(d.label, []);
      byParty.get(d.label).push(d);
    }
    for (const [p, rows] of byParty) {
      rows.sort((a, b) => a.year - b.year);
      const n = rows.length;
      for (let i = 0; i < n - 1; i++) {
        // segment_rank: 0 = oldest, n-1 = latest
        const rank = (i + 1) / Math.max(n - 1, 1);  // 0..1
        segs.push({
          ...rows[i], next_x: rows[i+1], rank,
          x1: rows[i],          // start point
          x2: rows[i+1]         // end point
        });
      }
    }
    return segs;
  }

  // ---------- Time-series plot ----------
  function renderTS(host, data) {
    host.innerHTML = "";
    const partiesIn = [...new Set(data.map(d => d.label))];
    if (partiesIn.length === 0) {
      host.innerHTML = '<p style="color:#888"><em>No parties selected.</em></p>';
      return;
    }
    const panels = [
      { dim: state.xDim, title: DIMS[state.xDim] },
      { dim: state.yDim, title: DIMS[state.yDim] }
    ];
    for (const p of panels) {
      const wrap = document.createElement("div");
      wrap.appendChild(Plot.plot({
        width: 900, height: 280, marginLeft: 50, marginBottom: 30, marginRight: 12,
        title: p.title,
        x: { label: "Election year", tickFormat: "d" },
        y: { domain: [0, 10], label: null, grid: true },
        color: { legend: false, domain: partiesIn, range: partiesIn.map(colourFor) },
        marks: [
          Plot.line(data, {
            x: "year", y: p.dim, stroke: "label",
            strokeWidth: 1.6, strokeOpacity: 0.85
          }),
          Plot.dot(data, {
            x: "year", y: p.dim, fill: "label", stroke: "label",
            r: 3.5, fillOpacity: 0.95,
            title: d => `${d.label} ${d.year}\n${DIMS[p.dim]}: ${d[p.dim]?.toFixed(2) ?? "—"}`
          })
        ]
      }));
      host.appendChild(wrap);
    }
  }

  // ---------- Scatter / trajectory plot ----------
  function renderScatter(host, data) {
    host.innerHTML = "";
    const partiesIn = [...new Set(data.map(d => d.label))];
    if (partiesIn.length === 0 || data.length === 0) {
      host.innerHTML = '<p style="color:#888"><em>No parties selected or no data in window.</em></p>';
      return;
    }
    const segs = makeSegments(data);
    // Latest manifesto per party (largest year)
    const latestByParty = new Map();
    for (const d of data) {
      const cur = latestByParty.get(d.label);
      if (!cur || d.year > cur.year) latestByParty.set(d.label, d);
    }
    const latest = [...latestByParty.values()];

    // Per-segment gradient: older segments have lower opacity
    const segWithOpacity = segs.map(s => ({
      ...s,
      // Linear: oldest segment opacity ~0.18, newest ~0.95
      opacity: 0.18 + 0.77 * s.rank
    }));

    host.appendChild(Plot.plot({
      width: 900, height: 580, marginLeft: 60, marginBottom: 50, marginRight: 20,
      caption: "Each line = one party's chronological path. " +
               "Faint segments are older; saturated segments are newest. " +
               "Years labelled on every point. Latest manifesto = bold ring + party label.",
      x: { domain: [0, 10], label: DIMS[state.xDim] + " →", grid: true },
      y: { domain: [0, 10], label: "↑ " + DIMS[state.yDim], grid: true },
      color: { legend: false, domain: partiesIn, range: partiesIn.map(colourFor) },
      marks: [
        // Quadrant lines at 5
        Plot.ruleX([5], { stroke: "#ccc", strokeDasharray: "3 3" }),
        Plot.ruleY([5], { stroke: "#ccc", strokeDasharray: "3 3" }),

        // Per-segment line with gradient opacity (one mark call per segment)
        Plot.link(segWithOpacity, {
          x1: d => d.x1[state.xDim], y1: d => d.x1[state.yDim],
          x2: d => d.x2[state.xDim], y2: d => d.x2[state.yDim],
          stroke: "label", strokeWidth: 2,
          strokeOpacity: "opacity",
          markerEnd: "arrow"
        }),

        // All points (small)
        Plot.dot(data, {
          x: state.xDim, y: state.yDim,
          fill: "label", stroke: "white", strokeWidth: 0.8, r: 4,
          title: d => `${d.label} ${d.year}\n${DIMS[state.xDim]}: ${d[state.xDim]?.toFixed(2)}\n${DIMS[state.yDim]}: ${d[state.yDim]?.toFixed(2)}`
        }),

        // Year text near each point (chronology cue)
        Plot.text(data, {
          x: state.xDim, y: state.yDim, text: "year",
          dy: -8, fontSize: 9, fill: "#444", stroke: "white", strokeWidth: 2.5
        }),

        // Latest manifesto: big ring + label
        Plot.dot(latest, {
          x: state.xDim, y: state.yDim,
          fill: "label", stroke: "black", strokeWidth: 1.3, r: 7
        }),
        Plot.text(latest, {
          x: state.xDim, y: state.yDim, text: "label",
          dx: 12, dy: -6, fontSize: 11, fontWeight: "bold",
          fill: "label", stroke: "white", strokeWidth: 3
        })
      ]
    }));
  }

  // ---------- Wire up everything ----------
  const tsHost = document.getElementById(tsId);
  const scHost = document.getElementById(scId);
  if (!tsHost || !scHost) {
    console.error("Country plots: missing target containers", tsId, scId);
    return;
  }

  // Insert a controls bar before the time-series plot
  const ctrls = document.createElement("div");
  ctrls.id = "country-ctrls";
  tsHost.parentNode.insertBefore(ctrls, tsHost);
  buildControls(ctrls);

  function refresh() {
    const data = filterData();
    renderTS(tsHost, data);
    renderScatter(scHost, data);
  }

  // Event handlers
  ctrls.querySelector("#x-dim").addEventListener("change", e => {
    state.xDim = e.target.value; refresh();
  });
  ctrls.querySelector("#y-dim").addEventListener("change", e => {
    state.yDim = e.target.value; refresh();
  });
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
  ctrls.querySelector("#select-all").addEventListener("click", () => {
    state.activeParties = new Set(allParties);
    ctrls.querySelectorAll('input[data-party]').forEach(cb => cb.checked = true);
    refresh();
  });
  ctrls.querySelector("#select-none").addEventListener("click", () => {
    state.activeParties = new Set();
    ctrls.querySelectorAll('input[data-party]').forEach(cb => cb.checked = false);
    refresh();
  });
  ctrls.querySelectorAll('input[data-party]').forEach(cb => {
    cb.addEventListener("change", () => {
      const p = cb.dataset.party;
      if (cb.checked) state.activeParties.add(p);
      else            state.activeParties.delete(p);
      refresh();
    });
  });

  refresh();
};
