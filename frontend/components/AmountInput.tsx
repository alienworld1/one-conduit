type AmountInputProps = {
  value: string;
  onChange: (v: string) => void;
  symbol: string;
  decimals: number;
  disabled?: boolean;
};

export function AmountInput({ value, onChange, symbol, decimals, disabled }: AmountInputProps) {
  return (
    <div>
      <label className="mb-2 block text-[11px] font-body tracking-widest text-text-muted uppercase">
        Amount
      </label>
      <div className="flex items-center rounded-sm border border-border bg-surface px-4 py-3">
        <input
          inputMode="decimal"
          value={value}
          disabled={disabled}
          placeholder="0"
          onChange={(e) => {
            const next = e.target.value;
            if (/^\d*\.?\d*$/.test(next)) {
              onChange(next);
            }
          }}
          className="w-full border-none bg-transparent font-data text-[28px] leading-none text-text-primary outline-none placeholder:text-text-muted"
          aria-label={`Amount in ${symbol} (${decimals} decimals)`}
        />
        <span className="ml-3 font-body text-[13px] text-text-muted">{symbol}</span>
      </div>
    </div>
  );
}
