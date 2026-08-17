import * as React from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "./dialog";

interface ConfirmDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description?: string;
  variant?: "default" | "danger";
  confirmLabel?: string;
  onConfirm: () => void | Promise<void>;
  disabled?: boolean;
  loading?: boolean;
}

export function ConfirmDialog({ open, onOpenChange, title, description, variant = "default", confirmLabel = "Confirm", onConfirm, disabled, loading: externalLoading }: ConfirmDialogProps) {
  const [internalLoading, setInternalLoading] = React.useState(false);
  const loading = externalLoading !== undefined ? externalLoading : internalLoading;

  const handleConfirm = async () => {
    setInternalLoading(true);
    try {
      await onConfirm();
    } finally {
      setInternalLoading(false);
      onOpenChange(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent style={{ maxWidth: "420px" }}>
        <DialogHeader>
          <DialogTitle style={{
            color: variant === "danger" ? "hsl(var(--danger-hover))" : undefined
          }}>
            {title}
          </DialogTitle>
          {description && <DialogDescription>{description}</DialogDescription>}
        </DialogHeader>
        <div style={{ display: "flex", gap: "0.625rem", justifyContent: "flex-end", marginTop: "1rem" }}>
          <button className="btn btn-secondary" onClick={() => onOpenChange(false)} disabled={loading}>Cancel</button>
          <button
            className={variant === "danger" ? "btn btn-danger" : "btn btn-primary"}
            onClick={handleConfirm}
            disabled={loading || disabled}
          >
            {loading ? "Processing..." : confirmLabel}
          </button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
