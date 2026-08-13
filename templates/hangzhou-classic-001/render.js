(() => {
  const manifest = window.__POSTER_MANIFEST__;

  document.getElementById("posterTitle").textContent =
    manifest.content.title;

  document.getElementById("posterSubtitle").textContent =
    manifest.content.subtitle;

  function createRoutePath(points, width, height) {
    if (!points.length) return "";

    const converted = points.map(point => ({
      x: point.x / 100 * width,
      y: point.y / 100 * height
    }));

    let path = `M ${converted[0].x} ${converted[0].y}`;

    for (let i = 1; i < converted.length; i++) {
      const previous = converted[i - 1];
      const current = converted[i];
      const middleX = (previous.x + current.x) / 2;

      path += `
        C ${middleX} ${previous.y},
          ${middleX} ${current.y},
          ${current.x} ${current.y}
      `;
    }

    return path;
  }

  function renderRoute() {
    const map = document.getElementById("routeMap");

    map.style.backgroundImage =
      `url("${manifest.assets.routeBackground.resolvedUrl}")`;

    const width = 365;
    const height = 400;
    const path = createRoutePath(
      manifest.route.points,
      width,
      height
    );

    map.innerHTML = `
      <svg
        viewBox="0 0 ${width} ${height}"
        preserveAspectRatio="none"
        class="route-lines"
      >
        <defs>
          <marker
            id="route-arrow"
            viewBox="0 0 10 10"
            refX="8"
            refY="5"
            markerWidth="6"
            markerHeight="6"
            orient="auto"
          >
            <path
              d="M 0 0 L 10 5 L 0 10 Z"
              fill="#356A43"
            />
          </marker>
        </defs>

        <path
          d="${path}"
          fill="none"
          stroke="#356A43"
          stroke-width="2.5"
          stroke-dasharray="7 6"
          marker-end="url(#route-arrow)"
        />
      </svg>
    `;

    manifest.content.itinerary.forEach(day => {
      const asset =
        manifest.assets[`day${day.day}`];

      const node = document.createElement("div");
      node.className = "route-node";
      node.style.left = `${day.visualPosition.x}%`;
      node.style.top = `${day.visualPosition.y}%`;
      node.style.setProperty("--day-color", day.color);

      node.innerHTML = `
        <div class="route-number">${day.day}</div>
        <div class="route-day">DAY ${day.day}</div>
        <img
          class="route-landmark"
          src="${asset.resolvedUrl}"
          alt="${day.theme}"
        />
        <div class="route-name">${day.theme}</div>
      `;

      map.appendChild(node);
    });
  }

  function renderSchedule() {
    const element = document.getElementById("schedule");

    element.innerHTML = manifest.content.itinerary
      .map(day => `
        <article
          class="day-row"
          style="--day-color:${day.color}"
        >
          <div class="day-index">
            <small>DAY</small>
            <strong>${day.day}</strong>
          </div>

          <div class="day-content">
            <h3>${day.theme}</h3>
            <p>${day.summary}</p>
          </div>

          <div class="day-price">
            <small>参考约</small>
            <strong>¥${day.estimatedCost}/人</strong>
          </div>
        </article>
      `)
      .join("");
  }

  function renderTips() {
    const element = document.getElementById("tips");

    element.innerHTML = manifest.content.tips
      .map(tip => {
        const icon = manifest.icons[tip.type];

        const mark = icon
          ? `<img
              class="tip-icon"
              src="${icon.resolvedUrl}"
              alt="${tip.type}"
            />`
          : `<span class="tip-check">✓</span>`;

        return `
          <div class="tip-row">
            ${mark}
            <span>${tip.text}</span>
          </div>
        `;
      })
      .join("");
  }

  function renderBudget() {
    const iconMap = {
      ticket: manifest.icons.ticket,
      food: manifest.icons.food,
      transport: manifest.icons.transport,
      other: manifest.icons.other
    };

    document.getElementById("budgetItems").innerHTML =
      manifest.content.budget.items
        .map(item => `
          <div class="budget-item">
            <div class="budget-name">${item.name}</div>
            <img
              src="${iconMap[item.type].resolvedUrl}"
              alt="${item.name}"
            />
            <div>约 ¥${item.amount}</div>
          </div>
        `)
        .join("");

    document.getElementById("budgetTotal").innerHTML = `
      <div class="total-label">预算合计</div>
      <strong>
        约 ¥ ${manifest.content.budget.total.toLocaleString("zh-CN")}/人
      </strong>
      <small>住宿及往返交通另计</small>
    `;
  }

  async function waitForImages() {
    const images = Array.from(document.images);

    await Promise.all(
      images.map(image => {
        if (image.complete && image.naturalWidth > 0) {
          return Promise.resolve();
        }

        return new Promise(resolve => {
          image.addEventListener("load", resolve, { once: true });
          image.addEventListener("error", resolve, { once: true });
        });
      })
    );
  }

  async function render() {
    renderRoute();
    renderSchedule();
    renderTips();
    renderBudget();

    await document.fonts.ready;
    await waitForImages();

    window.__POSTER_RENDER_READY__ = true;
  }

  render().catch(error => {
    window.__POSTER_RENDER_ERROR__ = error.message;
  });
})();