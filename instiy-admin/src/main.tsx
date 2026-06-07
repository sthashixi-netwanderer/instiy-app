import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import './index.css'
import App from './App.tsx'

const setupModalScrollLock = () => {
  const scrollbarWidth = window.innerWidth - document.documentElement.clientWidth
  document.documentElement.style.setProperty('--scrollbar-width', `${scrollbarWidth}px`)

  const update = () => {
    const hasModal = document.querySelector('.modal-backdrop') !== null
    document.body.classList.toggle('modal-open', hasModal)
  }

  const observer = new MutationObserver(update)
  observer.observe(document.body, { childList: true, subtree: true })
  update()
}

setupModalScrollLock()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </StrictMode>,
)

