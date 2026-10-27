/**
 * Party page: scores over time, one small panel per dimension (Observable Plot).
 * rows: {year, dim, score, model}; dims: [{id, label, min, max}]; models: [{id, short, colour}]
 * refs: {dim: {global: x, country: y}} reference means of the combined score.
 * Checkboxes toggle the per-model lines; the combined (cross-model) line is always shown.
 */
window.renderPartyPlot = async function (containerId, rows, dims, models, refs, countryName) {
  const Plot = await import("https://cdn.jsdelivr.net/npm/@observablehq/plot@0.6/+esm");
  const host = document.getElementById(containerId);
  if (!host) return;
  if (!rows || rows.length === 0) { host.innerHTML = "<p><em>No scores.</em></p>"; return; }
  const shown = new Set(["combined"]);
  const colour = Object.fromEntries(models.map(m => [m.short, m.colour]));
  const short = Object.fromEntries(models.map(m => [m.id, m.short]));
  const controls = document.createElement("div");
  controls.className = "party-plot-controls";
  controls.innerHTML = models.filter(m => m.id !== "combined").map(m =>
    `<label style="margin-right:1rem"><input type="checkbox" value="${m.id}"> <span style="color:${m.colour};font-weight:600">${m.short}</span></label>`
  ).join("") + `<span style="color:#666;font-size:.85em">Black line: cross-model mean (paper score). Solid grey: all manifestos; dashed: ${countryName}.</span>`;
  const panels = document.createElement("div");
  panels.style.display = "grid";
  panels.style.gridTemplateColumns = "repeat(auto-fill, minmax(330px, 1fr))";
  panels.style.gap = ".5rem 1.2rem";
  host.append(controls, panels);
  const years = rows.map(r => r.year);
  const xdom = [Math.min(...years) - 1, Math.max(...years) + 1];
  function draw() {
    panels.innerHTML = "";
    for (const d of dims) {
      const sub = rows.filter(r => r.dim === d.id && shown.has(r.model)).map(r => ({...r, m: short[r.model]}));
      const ref = refs[d.id] || {};
      const marks = [];
      if (ref.global != null) marks.push(Plot.ruleY([ref.global], {stroke: "#999"}));
      if (ref.country != null) marks.push(Plot.ruleY([ref.country], {stroke: "#999", strokeDasharray: "4,3"}));
      marks.push(Plot.line(sub, {x: "year", y: "score", stroke: "m", strokeWidth: r => r.model === "combined" ? 2.4 : 1.2, sort: "year"}));
      marks.push(Plot.dot(sub, {x: "year", y: "score", fill: "m", r: 3, tip: true,
        title: r => `${r.m} · ${r.year}\n${d.label}: ${r.score.toFixed(2)}`}));
      const fig = Plot.plot({
        width: 360, height: 190, marginLeft: 36, marginBottom: 24,
        x: {domain: xdom, tickFormat: "d", label: null, ticks: 6},
        y: {domain: [d.min, d.max], label: null, grid: true},
        color: {domain: Object.keys(colour), range: Object.values(colour)},
        marks
      });
      const wrap = document.createElement("div");
      wrap.innerHTML = `<div style="font-weight:600;font-size:.9rem;margin-top:.4rem">${d.label}</div>`;
      wrap.appendChild(fig);
      panels.appendChild(wrap);
    }
  }
  controls.querySelectorAll("input").forEach(cb => cb.addEventListener("change", e => {
    e.target.checked ? shown.add(e.target.value) : shown.delete(e.target.value); draw();
  }));
  draw();
};

/* Click-to-sort for tables with class "sortable" (numbers sort numerically, blanks last),
   and paging (10 rows per page, prev/next, page size) for tables with more than 10 rows. */
window.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("table.sortable").forEach(tbl => {
    const body = tbl.tBodies[0]; const rows = () => [...body.rows];
    const pg = {size: 10, page: 0};
    const bar = document.createElement("div"); bar.className = "table-pager";
    const show = () => {
      const r = rows(); const n = r.length; const pages = Math.max(1, Math.ceil(n / pg.size));
      pg.page = Math.min(pg.page, pages - 1);
      r.forEach((tr, i) => { tr.style.display = (pg.size >= n || (i >= pg.page * pg.size && i < (pg.page + 1) * pg.size)) ? "" : "none"; });
      if (n <= 10) { bar.style.display = "none"; return; }
      const first = pg.page * pg.size + 1, last = Math.min(n, (pg.page + 1) * pg.size);
      bar.innerHTML = `<button ${pg.page === 0 ? "disabled" : ""} data-go="-1">&#8249; previous</button>
        <span>${first}–${last} of ${n}</span>
        <button ${pg.page >= pages - 1 ? "disabled" : ""} data-go="1">next &#8250;</button>
        <label>rows per page <select>${[10, 25, 50, 1e9].map(s => `<option value="${s}" ${s === pg.size ? "selected" : ""}>${s > 1e8 ? "all" : s}</option>`).join("")}</select></label>`;
      bar.querySelectorAll("button").forEach(b => b.addEventListener("click", () => { pg.page += +b.dataset.go; show(); }));
      bar.querySelector("select").addEventListener("change", e => { pg.size = +e.target.value; pg.page = 0; show(); });
    };
    tbl.insertAdjacentElement("afterend", bar);
    tbl.addEventListener("sorted", () => { pg.page = 0; show(); });
    show();
    tbl.querySelectorAll("thead th").forEach((th, i) => {
      th.style.cursor = "pointer"; th.title = "Sort";
      th.addEventListener("click", () => {
        const body = tbl.tBodies[0]; const asc = th.dataset.dir !== "asc"; th.dataset.dir = asc ? "asc" : "desc";
        const val = tr => { const t = (tr.cells[i].dataset.v ?? tr.cells[i].textContent).trim(); const n = parseFloat(t); return t === "" || t === "–" ? null : (isNaN(n) ? t.toLowerCase() : n); };
        [...body.rows].sort((a, b) => { const x = val(a), y = val(b);
          if (x === null) return 1; if (y === null) return -1;
          return (x < y ? -1 : x > y ? 1 : 0) * (asc ? 1 : -1); }).forEach(r => body.appendChild(r));
        tbl.dispatchEvent(new Event("sorted"));
      });
    });
  });
});
