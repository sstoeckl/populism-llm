/**
 * Manifesto page client-side plot renderer.
 * Each manifesto page emits a small <script> that calls renderManifestoPlot(data).
 * Loads Observable Plot from CDN (cached across pages after first load).
 */
window.renderManifestoPlot = async function (containerId, data, opts) {
  const Plot = await import("https://cdn.jsdelivr.net/npm/@observablehq/plot@0.6/+esm");
  const container = document.getElementById(containerId);
  if (!container) return;
  if (!data || data.length === 0) {
    container.innerHTML = '<p style="color:#888"><em>No score data available.</em></p>';
    return;
  }
  const groupOrder = (opts && opts.groupOrder) || ["Populism", "Ideology", "Liberalism"];
  const dimOrder  = (opts && opts.dimOrder)  || [...new Set(data.map(d => d.dim_lbl))];
  const colourMap = {
    "Sonnet":       "#1b9e77",
    "gpt-4.1-mini": "#d95f02",
    "Gemini":       "#7570b3"
  };
  const symbolMap = {
    "Sonnet":       "circle",
    "gpt-4.1-mini": "triangle",
    "Gemini":       "square"
  };
  const groups = groupOrder.filter(g => data.some(d => d.group === g));
  for (const g of groups) {
    const sub = data.filter(d => d.group === g);
    const dims = dimOrder.filter(dl => sub.some(d => d.dim_lbl === dl));
    const h = Math.max(80, dims.length * 26 + 60);
    const wrap = document.createElement("div");
    wrap.innerHTML = `<h4 style="margin:.8rem 0 .2rem;color:#555">${g}</h4>`;
    const plot = Plot.plot({
      width: 760, height: h, marginLeft: 200, marginBottom: 28,
      x: { domain: [0, 10], ticks: 11, label: null, grid: true },
      y: { domain: dims.reverse(), label: null },
      color: { legend: true, domain: Object.keys(colourMap), range: Object.values(colourMap) },
      symbol: { legend: false, domain: Object.keys(symbolMap), range: Object.values(symbolMap) },
      marks: [
        Plot.dot(sub, {
          x: "score", y: "dim_lbl",
          fill: "model_lbl", stroke: "model_lbl", symbol: "model_lbl",
          r: 6, fillOpacity: 0.85
        })
      ]
    });
    wrap.appendChild(plot);
    container.appendChild(wrap);
  }
};
