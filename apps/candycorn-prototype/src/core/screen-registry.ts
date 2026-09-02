import type React from 'react';
import { routePaths, type ScreenId, type ScreenPath } from '@/core/routes';

export type PrimarySection = 'today' | 'journal' | 'prepare' | 'history' | 'settings' | null;
export interface PrototypeScreenDefinition {
  id: ScreenId;
  path: ScreenPath;
  title: string;
  reviewLabel: string;
  order: number;
  primarySection: PrimarySection;
  showBottomNav: boolean;
  component: React.ComponentType;
}
export interface PrototypeScreenModule { screens: readonly PrototypeScreenDefinition[] }

const maximumScreenCount = Object.keys(routePaths).length;

export function defineScreens(
  screens: readonly PrototypeScreenDefinition[],
): readonly PrototypeScreenDefinition[] {
  if (screens.length === 0 || screens.length > maximumScreenCount) {
    throw new RangeError(`A screen module must define between 1 and ${maximumScreenCount} screens.`);
  }
  const knownPaths = new Set<ScreenPath>(Object.values(routePaths));
  screens.forEach((screen) => {
    if (routePaths[screen.id] !== screen.path || !knownPaths.has(screen.path)) {
      throw new Error(`Screen ${screen.id} must use its canonical route path.`);
    }
    if (!screen.title.trim() || !screen.reviewLabel.trim() || !Number.isSafeInteger(screen.order)) {
      throw new Error(`Screen ${screen.id} has invalid display metadata.`);
    }
  });
  return Object.freeze([...screens]);
}

export function collectScreens(
  modules: Readonly<Record<string, PrototypeScreenModule>>,
): readonly PrototypeScreenDefinition[] {
  const moduleEntries = Object.entries(modules) as Array<[string, PrototypeScreenModule]>;
  if (moduleEntries.length > maximumScreenCount) {
    throw new RangeError(`Feature module count exceeds the ${maximumScreenCount}-screen contract.`);
  }
  const screens = moduleEntries.flatMap(([modulePath, moduleValue]) => {
    const exportedScreens: unknown = moduleValue.screens;
    if (!Array.isArray(exportedScreens)) {
      throw new TypeError(`${modulePath} must export a screens array.`);
    }
    return exportedScreens as PrototypeScreenDefinition[];
  });
  if (screens.length > maximumScreenCount) {
    throw new RangeError(`Discovered more than ${maximumScreenCount} prototype screens.`);
  }
  const ids = new Set<ScreenId>();
  const paths = new Set<ScreenPath>();
  const orders = new Set<number>();
  screens.forEach((screen) => {
    if (ids.has(screen.id) || paths.has(screen.path) || orders.has(screen.order)) {
      throw new Error(`Duplicate screen definition detected for ${screen.id} (${screen.path}, order ${screen.order}).`);
    }
    if (routePaths[screen.id] !== screen.path) {
      throw new Error(`Screen ${screen.id} does not match its canonical route path.`);
    }
    ids.add(screen.id);
    paths.add(screen.path);
    orders.add(screen.order);
  });
  return Object.freeze([...screens].sort((first, second) => first.order - second.order));
}
