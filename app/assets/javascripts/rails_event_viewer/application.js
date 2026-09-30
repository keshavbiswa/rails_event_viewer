document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-event-viewer-width]").forEach((bar) => {
    bar.style.width = `${bar.dataset.eventViewerWidth}%`
  })
})

document.addEventListener("click", (event) => {
  const copyButton = event.target.closest("[data-event-viewer-copy]")
  if (copyButton) {
    if (!navigator.clipboard || copyButton.dataset.eventViewerCopied) return

    navigator.clipboard.writeText(copyButton.dataset.eventViewerCopy).then(() => {
      const label = copyButton.textContent
      copyButton.dataset.eventViewerCopied = "true"
      copyButton.textContent = "Copied!"
      setTimeout(() => {
        copyButton.textContent = label
        delete copyButton.dataset.eventViewerCopied
      }, 1500)
    })
    return
  }

  const row = event.target.closest("[data-event-viewer-href]")
  if (row && !event.target.closest("a, button")) {
    window.location = row.dataset.eventViewerHref
  }
})
