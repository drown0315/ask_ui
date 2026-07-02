import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { AskUiWorkbench } from './app/AskUiWorkbench';
import './app/AskUiWorkbench.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <AskUiWorkbench />
  </StrictMode>,
);
