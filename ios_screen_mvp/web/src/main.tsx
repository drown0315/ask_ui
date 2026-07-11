import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'

import { IosScreenDemo } from './IosScreenDemo'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <IosScreenDemo />
  </StrictMode>,
)
