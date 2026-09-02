import { useRef, type KeyboardEvent } from 'react';

export interface SelectableTabsProps<T extends string> {
  items: readonly { value: T; label: string }[];
  value: T;
  onChange(value: T): void;
  ariaLabel: string;
}

export function SelectableTabs<T extends string>({
  items,
  value,
  onChange,
  ariaLabel,
}: SelectableTabsProps<T>) {
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([]);
  if (items.length === 0 || items.length > 8) {
    throw new RangeError('SelectableTabs supports between 1 and 8 items.');
  }
  if (!items.some((item) => item.value === value)) {
    throw new Error('SelectableTabs value must match one of its items.');
  }

  function moveSelection(event: KeyboardEvent<HTMLButtonElement>, currentIndex: number) {
    const direction = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
    if (direction === 0) return;
    event.preventDefault();
    const nextIndex = (currentIndex + direction + items.length) % items.length;
    const nextItem = items[nextIndex];
    if (nextItem === undefined) throw new RangeError('Tab navigation resolved outside the item list.');
    onChange(nextItem.value);
    tabRefs.current[nextIndex]?.focus();
  }

  return (
    <div className="cc-tabs" role="tablist" aria-label={ariaLabel}>
      {items.map((item, index) => (
        <button
          key={item.value}
          ref={(element) => { tabRefs.current[index] = element; }}
          type="button"
          role="tab"
          aria-selected={item.value === value}
          tabIndex={item.value === value ? 0 : -1}
          className="cc-tab"
          onClick={() => onChange(item.value)}
          onKeyDown={(event) => moveSelection(event, index)}
        >
          {item.label}
        </button>
      ))}
    </div>
  );
}
