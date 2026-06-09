import { tauriFetch } from './polyfills/tauri'

export function getUniversalFetch() {
    return tauriFetch
}
