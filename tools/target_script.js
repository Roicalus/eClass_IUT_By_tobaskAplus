const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const prefersCoarsePointer = window.matchMedia("(pointer: coarse)");
const prefersCompactViewport = window.matchMedia("(max-width: 820px)");

function useLiteExperience() {
  return (
    prefersReducedMotion.matches ||
    prefersCoarsePointer.matches ||
    prefersCompactViewport.matches
  );
}

document.addEventListener("DOMContentLoaded", () => {
  setupMobileNav();
  setupSmoothScroll();
  setupRevealAnimations();
  setupComparisonGallery();

  if (!useLiteExperience()) {
    setupHeroParallax();
  }
});

function setupMobileNav() {
  const nav = document.querySelector(".nav");
  const toggle = document.querySelector(".nav-toggle");
  const menuLinks = document.querySelectorAll(".nav-menu a[href^='#']");

  if (!nav || !toggle) {
    return;
  }

  const closeMenu = () => {
    nav.classList.remove("is-open");
    toggle.setAttribute("aria-expanded", "false");
    document.body.classList.remove("menu-open");
  };

  toggle.addEventListener("click", () => {
    const isOpen = nav.classList.toggle("is-open");
    toggle.setAttribute("aria-expanded", String(isOpen));
    document.body.classList.toggle("menu-open", isOpen);
  });

  menuLinks.forEach((link) => {
    link.addEventListener("click", closeMenu);
  });

  window.addEventListener("resize", () => {
    if (window.innerWidth > 820) {
      closeMenu();
    }
  });

  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closeMenu();
    }
  });
}

function setupSmoothScroll() {
  const header = document.querySelector(".site-header");
  const anchorLinks = document.querySelectorAll('a[href^="#"]');

  anchorLinks.forEach((link) => {
    link.addEventListener("click", (event) => {
      const targetId = link.getAttribute("href");

      if (!targetId || targetId === "#") {
        return;
      }

      const target = document.querySelector(targetId);

      if (!target) {
        return;
      }

      event.preventDefault();

      const headerOffset = header ? header.offsetHeight - 6 : 0;
      const targetTop =
        target.getBoundingClientRect().top + window.scrollY - headerOffset;

      window.scrollTo({
        top: Math.max(targetTop, 0),
        behavior: useLiteExperience() ? "auto" : "smooth",
      });
    });
  });
}

function setupRevealAnimations() {
  const revealElements = document.querySelectorAll("[data-reveal]");

  if (!revealElements.length) {
    return;
  }

  if (!("IntersectionObserver" in window) || useLiteExperience()) {
    revealElements.forEach((element) => element.classList.add("is-visible"));
    return;
  }

  const observer = new IntersectionObserver(
    (entries, activeObserver) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) {
          return;
        }

        entry.target.classList.add("is-visible");
        activeObserver.unobserve(entry.target);
      });
    },
    {
      threshold: 0.18,
      rootMargin: "0px 0px -8% 0px",
    }
  );

  revealElements.forEach((element, index) => {
    element.style.transitionDelay = `${Math.min(index * 70, 240)}ms`;
    observer.observe(element);
  });
}

function setupComparisonGallery() {
  const isLite = useLiteExperience();
  const section = document.querySelector(".comparison-section");
  if (!section) {
    return;
  }

  const comparisonData = {
    courses: {
      label: "Courses",
      insight: {
        frictionScore: "73",
        frictionText: "Users hunt across multiple surfaces.",
        clarityScore: "92",
        clarityText: "Key actions remain visible and guided.",
      },
      oldScreen: {
        title: "Navigation overload",
        copy: "Dense menus and weak hierarchy make core actions harder to locate.",
        src: "Comparisons/optimized/Old%201(courses).webp",
        alt: "Old courses screen comparison",
      },
      newScreen: {
        title: "Courses at a glance",
        copy: "Strong visual structure makes the next step clear in seconds.",
        src: "Comparisons/optimized/New%201(courses).webp",
        alt: "E-class courses screen comparison",
      },
    },
    "course-info": {
      label: "Course Info",
      insight: {
        frictionScore: "68",
        frictionText: "Important details compete with secondary content.",
        clarityScore: "94",
        clarityText: "Assignments and context are grouped in one readable flow.",
      },
      oldScreen: {
        title: "Details feel buried",
        copy: "Key information competes with secondary content and slows comprehension.",
        src: "Comparisons/optimized/Old%202(course%20info).webp",
        alt: "Old course info screen comparison",
      },
      newScreen: {
        title: "Course context first",
        copy: "Critical context is surfaced in a calm layout that reads naturally on mobile.",
        src: "Comparisons/optimized/New%202(course%20info).webp",
        alt: "E-class course info screen comparison",
      },
    },
    grades: {
      label: "Grades",
      insight: {
        frictionScore: "77",
        frictionText: "Performance signals feel fragmented and hard to interpret.",
        clarityScore: "95",
        clarityText: "Academic progress becomes scanable with clear visual hierarchy.",
      },
      oldScreen: {
        title: "Progress feels fragmented",
        copy: "The grading view looks functional but does not explain progress clearly.",
        src: "Comparisons/optimized/Old%203(grades%20system).webp",
        alt: "Old grades screen comparison",
      },
      newScreen: {
        title: "Grades with meaning",
        copy: "Academic performance becomes easier to read, scan, and trust at a glance.",
        src: "Comparisons/optimized/New%203(grades%20system).webp",
        alt: "E-class grades screen comparison",
      },
    },
    login: {
      label: "Login",
      insight: {
        frictionScore: "64",
        frictionText: "The first touchpoint feels generic and low-confidence.",
        clarityScore: "93",
        clarityText: "The welcome flow looks modern and product-led immediately.",
      },
      oldScreen: {
        title: "A dated first impression",
        copy: "The entry flow feels generic and offers little product confidence up front.",
        src: "Comparisons/optimized/Old%204(log%20in).webp",
        alt: "Old login screen comparison",
      },
      newScreen: {
        title: "A calmer welcome flow",
        copy: "The new entry point feels product-led, modern, and much more intentional.",
        src: "Comparisons/optimized/New%204(log%20in).webp",
        alt: "E-class login screen comparison",
      },
    },
  };

  if (isLite) {
    setupComparisonGalleryMobile(comparisonData);
    return;
  }

  const tabs = document.querySelectorAll(".comparison-tab");
  const steps = document.querySelectorAll(".comparison-step");
  const sticky = document.querySelector(".comparison-sticky");
  const oldTitle = document.querySelector("#comparison-old-title");
  const oldCopy = document.querySelector("#comparison-old-copy");
  const oldImage = document.querySelector("#comparison-old-image");
  const newTitle = document.querySelector("#comparison-new-title");
  const newCopy = document.querySelector("#comparison-new-copy");
  const newImage = document.querySelector("#comparison-new-image");
  const progressValue = document.querySelector("#comparison-progress-value");
  const sceneTitle = document.querySelector("#comparison-scene-title");
  const sceneIndex = document.querySelector("#comparison-scene-index");
  const sceneMeterFill = document.querySelector(".comparison-scene-meter-fill");
  const activeKicker = document.querySelector("#comparison-active-kicker");
  const activeTitle = document.querySelector("#comparison-active-title");
  const activeText = document.querySelector("#comparison-active-text");
  const frictionScore = document.querySelector("#comparison-friction-score");
  const frictionText = document.querySelector("#comparison-friction-text");
  const clarityScore = document.querySelector("#comparison-clarity-score");
  const clarityText = document.querySelector("#comparison-clarity-text");

  if (
    !tabs.length ||
    !steps.length ||
    !sticky ||
    !oldTitle ||
    !oldCopy ||
    !oldImage ||
    !newTitle ||
    !newCopy ||
    !newImage ||
    !progressValue ||
    !sceneTitle ||
    !sceneIndex ||
    !sceneMeterFill ||
    !activeKicker ||
    !activeTitle ||
    !activeText ||
    !frictionScore ||
    !frictionText ||
    !clarityScore ||
    !clarityText
  ) {
    return;
  }

  const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
  const easeInOutCubic = (value) =>
    value < 0.5
      ? 4 * value * value * value
      : 1 - Math.pow(-2 * value + 2, 3) / 2;
  const getFocusY = () => window.innerHeight * 0.48;
  const stepOrder = Array.from(steps);

  let currentKey = "";
  let currentProgress = -1;
  let currentStoryProgress = -1;
  let currentActiveStepId = "";
  let isSectionVisible = false;
  let sceneFrame = 0;

  const syncActiveState = (key) => {
    tabs.forEach((tab) => {
      const isActive = tab.dataset.comparison === key;
      tab.classList.toggle("is-active", isActive);
      tab.setAttribute("aria-selected", String(isActive));
    });

    steps.forEach((step) => {
      const isActive = step.dataset.comparison === key;
      step.classList.toggle("is-active", isActive);
      step.setAttribute("aria-current", isActive ? "step" : "false");
    });
  };

  const syncComparisonContent = (key) => {
    const data = comparisonData[key];

    if (!data || currentKey === key) {
      return;
    }

    oldTitle.textContent = data.oldScreen.title;
    oldCopy.textContent = data.oldScreen.copy;
    oldImage.src = data.oldScreen.src;
    oldImage.alt = data.oldScreen.alt;
    oldImage.loading = "lazy";
    oldImage.decoding = "async";

    newTitle.textContent = data.newScreen.title;
    newCopy.textContent = data.newScreen.copy;
    newImage.src = data.newScreen.src;
    newImage.alt = data.newScreen.alt;
    newImage.loading = "lazy";
    newImage.decoding = "async";

    frictionScore.textContent = data.insight.frictionScore;
    frictionText.textContent = data.insight.frictionText;
    clarityScore.textContent = data.insight.clarityScore;
    clarityText.textContent = data.insight.clarityText;

    currentKey = key;
    syncActiveState(key);
  };

  const syncSceneMeta = (step, progress) => {
    const key = step.dataset.comparison || "courses";
    const title = comparisonData[key]?.label || "Flow";
    const index = stepOrder.indexOf(step);
    const stepLabel = `${String(index + 1).padStart(2, "0")} / ${String(stepOrder.length).padStart(2, "0")}`;
    const storyProgress = clamp(((index + progress) / stepOrder.length) * 100, 0, 100);

    sceneTitle.textContent = title;
    sceneIndex.textContent = stepLabel;

    if (Math.abs(storyProgress - currentStoryProgress) >= 0.5) {
      sticky.style.setProperty("--comparison-story-progress", `${storyProgress.toFixed(2)}%`);
      sceneMeterFill.style.width = `${storyProgress.toFixed(2)}%`;
      currentStoryProgress = storyProgress;
    }
  };

  const syncActiveNarrative = (step) => {
    const stepId = step.id || step.dataset.comparison;

    if (stepId === currentActiveStepId) {
      return;
    }

    const kicker = step.querySelector(".comparison-step-kicker")?.textContent?.trim() || "";
    const title = step.querySelector("h3")?.textContent?.trim() || "";
    const copy = step.querySelector("p:last-child")?.textContent?.trim() || "";

    activeKicker.textContent = kicker;
    activeTitle.textContent = title;
    activeText.textContent = copy;
    currentActiveStepId = stepId;
  };

  const syncStepProgress = (activeStep, progress) => {
    const activeIndex = stepOrder.indexOf(activeStep);

    stepOrder.forEach((step, index) => {
      let stepProgress = 0;

      if (index < activeIndex) {
        stepProgress = 1;
      } else if (index === activeIndex) {
        stepProgress = progress;
      }

      step.style.setProperty("--step-progress", stepProgress.toFixed(3));
    });
  };

  const syncProgress = (progress) => {
    const clampedProgress = clamp(progress, 0, 1);
    const replacementProgress = easeInOutCubic(clampedProgress);

    if (Math.abs(replacementProgress - currentProgress) < 0.01) {
      return;
    }

    sticky.style.setProperty(
      "--comparison-progress",
      replacementProgress.toFixed(3)
    );
    sticky.style.setProperty(
      "--comparison-reveal",
      `${((1 - replacementProgress) * 100).toFixed(2)}%`
    );
    sticky.style.setProperty("--comparison-shift", `${(replacementProgress * 30).toFixed(2)}px`);
    progressValue.textContent = `${Math.round(replacementProgress * 100)}%`;
    currentProgress = replacementProgress;
  };

  const getActiveStep = () => {
    let closestStep = steps[0];
    let smallestDistance = Number.POSITIVE_INFINITY;
    const focusY = getFocusY();

    for (const step of steps) {
      const rect = step.getBoundingClientRect();

      if (rect.top <= focusY && rect.bottom >= focusY) {
        return step;
      }

      const distance = rect.top > focusY
        ? rect.top - focusY
        : focusY - rect.bottom;

      if (distance < smallestDistance) {
        smallestDistance = distance;
        closestStep = step;
      }
    }

    return closestStep;
  };

  const getStepProgress = (step) => {
    const rect = step.getBoundingClientRect();
    const focusY = getFocusY();
    const safeHeight = Math.max(rect.height, 1);

    return clamp((focusY - rect.top) / safeHeight, 0, 1);
  };

  const updateScene = () => {
    sceneFrame = 0;

    if (!isSectionVisible) {
      return;
    }

    const activeStep = getActiveStep();
    const key = activeStep.dataset.comparison;
    const stepProgress = getStepProgress(activeStep);

    syncComparisonContent(key);
    syncActiveState(key);
    syncSceneMeta(activeStep, stepProgress);
    syncActiveNarrative(activeStep);
    syncStepProgress(activeStep, stepProgress);
    syncProgress(stepProgress);
  };

  const requestSceneUpdate = () => {
    if (!sceneFrame) {
      sceneFrame = window.requestAnimationFrame(updateScene);
    }
  };

  if ("IntersectionObserver" in window) {
    const sectionObserver = new IntersectionObserver(
      (entries) => {
        isSectionVisible = entries.some((entry) => entry.isIntersecting);

        if (isSectionVisible) {
          requestSceneUpdate();
        }
      },
      {
        rootMargin: "0px 0px -10% 0px",
      }
    );

    sectionObserver.observe(section);
  } else {
    isSectionVisible = true;
  }

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      const targetStep = Array.from(steps).find(
        (step) => step.dataset.comparison === tab.dataset.comparison
      );

      if (targetStep) {
        targetStep.scrollIntoView({
          behavior: useLiteExperience() ? "auto" : "smooth",
          block: "center",
        });
      }

      syncComparisonContent(tab.dataset.comparison);
      syncProgress(0.02);
      requestSceneUpdate();
    });
  });

  window.addEventListener("scroll", requestSceneUpdate, { passive: true });
  window.addEventListener("resize", requestSceneUpdate);
  window.addEventListener("orientationchange", requestSceneUpdate);

  syncComparisonContent("courses");
  syncSceneMeta(stepOrder[0], 0);
  syncActiveNarrative(stepOrder[0]);
  syncStepProgress(stepOrder[0], 0);
  syncProgress(0);
}

function setupComparisonGalleryMobile(comparisonData) {
  const root = document.querySelector("#comparison-mobile");
  const track = document.querySelector("#comparison-mobile-track");
  const label = document.querySelector("#comparison-mobile-label");
  const index = document.querySelector("#comparison-mobile-index");
  const progressFill = document.querySelector("#comparison-mobile-progress-fill");

  if (!root || !track || !label || !index || !progressFill) {
    return;
  }

  const keys = Object.keys(comparisonData);

  if (!keys.length) {
    return;
  }

  track.innerHTML = keys
    .map((key, sceneIndex) => {
      const data = comparisonData[key];

      return `
        <article class="comparison-mobile-card${sceneIndex === 0 ? " is-active" : ""}" data-comparison="${key}" data-index="${sceneIndex}" role="listitem">
          <p class="comparison-mobile-kicker">${data.label}</p>
          <div class="comparison-mobile-viewport" style="--mobile-reveal: 50%;">
            <img
              class="comparison-mobile-image comparison-mobile-image-old"
              src="${data.oldScreen.src}"
              alt="${data.oldScreen.alt}"
              loading="lazy"
              decoding="async"
              width="1080"
              height="2224"
            />
            <img
              class="comparison-mobile-image comparison-mobile-image-new"
              src="${data.newScreen.src}"
              alt="${data.newScreen.alt}"
              loading="lazy"
              decoding="async"
              width="1080"
              height="2224"
            />
            <span class="comparison-mobile-divider" aria-hidden="true"></span>
          </div>
          <label class="comparison-mobile-scrub">
            <span>E-class</span>
            <input class="comparison-mobile-range" type="range" min="0" max="100" value="50" aria-label="Reveal comparison for ${data.label}" />
            <span>E-class</span>
            <output class="comparison-mobile-percent">50%</output>
          </label>
          <h3>${data.newScreen.title}</h3>
          <p>${data.newScreen.copy}</p>
          <div class="comparison-mobile-metrics">
            <div class="comparison-mobile-metric E-class">
              <span>Friction</span>
              <strong>${data.insight.frictionScore}</strong>
            </div>
            <div class="comparison-mobile-metric modern">
              <span>Clarity</span>
              <strong>${data.insight.clarityScore}</strong>
            </div>
          </div>
        </article>
      `;
    })
    .join("");

  const cards = Array.from(track.querySelectorAll(".comparison-mobile-card"));

  if (!cards.length) {
    return;
  }

  const setCardReveal = (card, value) => {
    const viewport = card.querySelector(".comparison-mobile-viewport");
    const percent = card.querySelector(".comparison-mobile-percent");

    if (!viewport || !percent) {
      return;
    }

    const normalizedValue = Math.max(0, Math.min(100, Number(value) || 0));
    viewport.style.setProperty("--mobile-reveal", `${normalizedValue}%`);
    percent.textContent = `${normalizedValue}%`;
  };

  cards.forEach((card) => {
    const range = card.querySelector(".comparison-mobile-range");

    if (!range) {
      return;
    }

    setCardReveal(card, range.value);

    range.addEventListener("input", () => {
      setCardReveal(card, range.value);
    });
  });

  const updateActiveCard = (sceneIndex) => {
    const normalizedIndex = Math.max(0, Math.min(cards.length - 1, sceneIndex));
    const key = cards[normalizedIndex].dataset.comparison || keys[0];
    const data = comparisonData[key] || comparisonData[keys[0]];
    const storyProgress = ((normalizedIndex + 1) / cards.length) * 100;

    cards.forEach((card, indexValue) => {
      card.classList.toggle("is-active", indexValue === normalizedIndex);
    });

    label.textContent = data.label;
    index.textContent = `${String(normalizedIndex + 1).padStart(2, "0")} / ${String(cards.length).padStart(2, "0")}`;
    progressFill.style.width = `${storyProgress.toFixed(2)}%`;
  };

  updateActiveCard(0);

  if ("IntersectionObserver" in window) {
    const mobileObserver = new IntersectionObserver(
      (entries) => {
        let strongestEntry = null;

        entries.forEach((entry) => {
          if (!entry.isIntersecting) {
            return;
          }

          if (!strongestEntry || entry.intersectionRatio > strongestEntry.intersectionRatio) {
            strongestEntry = entry;
          }
        });

        if (!strongestEntry) {
          return;
        }

        const sceneIndex = Number(strongestEntry.target.dataset.index || 0);
        updateActiveCard(sceneIndex);
      },
      {
        root: track,
        threshold: [0.52, 0.66, 0.82],
      }
    );

    cards.forEach((card) => {
      mobileObserver.observe(card);
    });
  }
}

function setupHeroParallax() {
  const heroVisual = document.querySelector("[data-parallax]");
  const cardFrame = document.querySelector(".hero-card-frame");

  if (!heroVisual || !cardFrame) {
    return;
  }

  const state = {
    x: 0,
    y: 0,
    frame: 0,
  };

  const updateCard = () => {
    cardFrame.style.setProperty("--parallax-x", `${state.x * 12}px`);
    cardFrame.style.setProperty("--parallax-y", `${state.y * 12}px`);
    cardFrame.style.setProperty("--tilt-x", `${state.y * -5}deg`);
    cardFrame.style.setProperty("--tilt-y", `${state.x * 7}deg`);
    state.frame = 0;
  };

  const requestUpdate = () => {
    if (!state.frame) {
      state.frame = window.requestAnimationFrame(updateCard);
    }
  };

  heroVisual.addEventListener("mousemove", (event) => {
    const bounds = heroVisual.getBoundingClientRect();
    const relativeX = (event.clientX - bounds.left) / bounds.width;
    const relativeY = (event.clientY - bounds.top) / bounds.height;

    state.x = (relativeX - 0.5) * 2;
    state.y = (relativeY - 0.5) * 2;
    requestUpdate();
  });

  heroVisual.addEventListener("mouseleave", () => {
    state.x = 0;
    state.y = 0;
    requestUpdate();
  });

  let scrollFrame = 0;

  const syncScrollDepth = () => {
    const bounds = heroVisual.getBoundingClientRect();
    const visibleRatio = 1 - Math.min(Math.abs(bounds.top) / window.innerHeight, 1);
    heroVisual.style.transform = `translateY(${visibleRatio * -10}px)`;
    scrollFrame = 0;
  };

  window.addEventListener(
    "scroll",
    () => {
      if (!scrollFrame) {
        scrollFrame = window.requestAnimationFrame(syncScrollDepth);
      }
    },
    { passive: true }
  );

  syncScrollDepth();
}

