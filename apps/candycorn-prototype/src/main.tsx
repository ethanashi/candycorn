import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { HashRouter } from 'react-router-dom';
import { App } from '@/App';
import { DemoStateProvider } from '@/core/demo-state';
import '@/styles/tokens.css';
import '@/styles/base.css';

const rootElement = document.getElementById('root');

if (!(rootElement instanceof HTMLElement)) {
  throw new Error('Candy Corn could not find its root element.');
}

createRoot(rootElement).render(
  <StrictMode>
    <HashRouter>
      <DemoStateProvider>
        <App />
      </DemoStateProvider>
    </HashRouter>
  </StrictMode>,
);
