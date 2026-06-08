/**
 * Country page plots: time-series + Populism × Liberalism trajectories.
 *
 * Each plot_data row = one party-year manifesto with fields:
 *   doc_id, year, party, partyabbrev, partyname,
 *   populism_overall, liberalism_overall, pop_ideology_overall, label
 *
 * Data is already filtered to parties with ≥ 2 manifestos so trajectories are meaningful.
 */
window.renderCountryPlots = async function (tsId, scId, plotData, countryName) {
  const Plot = await import("https://cdn.jsdelivr.net/npm/@observablehq/plot@0.6/+esm");

  // ---------- Stable colour assignment per party ----------
  const parties = [...new Set(plotData.map(d => d.label))].sort();
  // Tableau-style 20-colour palette + cycling for >20 parties
  const palette = [
    "#1f77b4","#ff7f0e","#2ca02c","#d62728","#9467bd",
    "#8c564b","#e377c2","#7f7f7f","#bcbd22","#17becf",
    "#aec7e8","#ffbb78","#98df8a","#ff9896","#c5b0d5",
    "#c49c94","#f7b6d2","#c7c7c7","#dbdb8d","#9edae5"
  ];
  const colourFor = p => palette[parties.indexOf(p) % palette.length];

  // ---------- TIME-SERIES: populism + liberalism per party over years ----------
  const tsContainer = document.getElementById(tsId);
  if (tsContainer && plotData.length) {
    const wrap = document.createElement("div");
    // Populism panel
    const popPanel = Plot.plot({
      width: 900, height: 320, marginLeft: 50, marginBottom: 30, marginRight: 12,
      title: "Populism overall",
      x: { label: "Election year", tickFormat: "d" },
      y: { domain: [0, 10], label: null, grid: true },
      color: { legend: true, domain: parties, range: parties.map(colourFor) },
      marks: [
        Plot.line(plotData, {
          x: "year", y: "populism_overall", stroke: "label", strokeWidth: 1.4
        }),
        Plot.dot(plotData, {
          x: "year", y: "populism_overall", fill: "label", stroke: "label",
          r: 3.5, fillOpacity: 0.9,
          title: d => `${d.label} ${d.year}\npop = ${d.populism_overall?.toFixed(2)}`
        })
      ]
    });
    wrap.appendChild(popPanel);

    // Liberalism panel
    const libPanel = Plot.plot({
      width: 900, height: 320, marginLeft: 50, marginBottom: 30, marginRight: 12,
      title: "Liberalism overall",
      x: { label: "Election year", tickFormat: "d" },
      y: { domain: [0, 10], label: null, grid: true },
      color: { domain: parties, range: parties.map(colourFor) },
      marks: [
        Plot.line(plotData, {
          x: "year", y: "liberalism_overall", stroke: "label", strokeWidth: 1.4
        }),
        Plot.dot(plotData, {
          x: "year", y: "liberalism_overall", fill: "label", stroke: "label",
          r: 3.5, fillOpacity: 0.9,
          title: d => `${d.label} ${d.year}\nlib = ${d.liberalism_overall?.toFixed(2)}`
        })
      ]
    });
    wrap.appendChild(libPanel);

    tsContainer.appendChild(wrap);
  }

  // ---------- SCATTER: Populism × Liberalism with chronological trajectories ----------
  const scContainer = document.getElementById(scId);
  if (scContainer && plotData.length) {
    // For each party, draw a path connecting its points in time order
    const traj = parties.flatMap(p => {
      const pts = plotData.filter(d => d.label === p)
        .sort((a, b) => a.year - b.year);
      return pts;
    });

    // Plot the path AND the points; the latest point is bigger (=current state)
    const partyLast = {};
    parties.forEach(p => {
      const pts = plotData.filter(d => d.label === p).sort((a, b) => a.year - b.year);
      if (pts.length) partyLast[p] = pts[pts.length - 1];
    });
    const lastPoints = Object.values(partyLast);

    const sc = Plot.plot({
      width: 900, height: 560, marginLeft: 60, marginBottom: 50, marginRight: 20,
      title: "Populism × Liberalism — each party's trajectory over time",
      caption: "Lines connect each party's manifestos in chronological order. " +
               "Larger dot = most recent manifesto.",
      x: { domain: [0, 10], label: "Populism (overall) →", grid: true },
      y: { domain: [0, 10], label: "↑ Liberalism (overall)", grid: true },
      color: { legend: true, domain: parties, range: parties.map(colourFor) },
      marks: [
        // Faint quadrant lines at 5
        Plot.ruleX([5], { stroke: "#ccc", strokeDasharray: "3 3" }),
        Plot.ruleY([5], { stroke: "#ccc", strokeDasharray: "3 3" }),
        // Trajectories
        Plot.line(traj, {
          x: "populism_overall", y: "liberalism_overall",
          z: "label", stroke: "label", strokeWidth: 1.2, strokeOpacity: 0.55,
          curve: "linear",
          markerStart: "dot", markerEnd: "arrow"
        }),
        // Each manifesto point (small)
        Plot.dot(plotData, {
          x: "populism_overall", y: "liberalism_overall",
          fill: "label", stroke: "white", strokeWidth: 0.5, r: 3,
          title: d => `${d.label} ${d.year}\npop = ${d.populism_overall?.toFixed(2)}\nlib = ${d.liberalism_overall?.toFixed(2)}`
        }),
        // Most recent manifesto (large)
        Plot.dot(lastPoints, {
          x: "populism_overall", y: "liberalism_overall",
          fill: "label", stroke: "black", strokeWidth: 1.3, r: 7
        }),
        // Label the most recent
        Plot.text(lastPoints, {
          x: "populism_overall", y: "liberalism_overall",
          text: "label", dx: 10, dy: -4, fontSize: 11, fontWeight: "bold",
          fill: "label", stroke: "white", strokeWidth: 3
        })
      ]
    });
    scContainer.appendChild(sc);
  }
};
