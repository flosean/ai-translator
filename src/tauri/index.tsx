import './legacy-tauri-ipc'
import './index.css'
import { createRoot } from 'react-dom/client'
import { App } from './App'

import { GlobalSuspense } from '../common/components/GlobalSuspense'

import '../common/i18n.js'

const root = createRoot(document.getElementById('root')!)

root.render(
    <GlobalSuspense>
        <App />
    </GlobalSuspense>
)
