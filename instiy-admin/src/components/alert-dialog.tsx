import * as React from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "./dialog";

interface AlertDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description?: string;
  variant?: "default" | "danger" | "success" | "error" | "info";
  children?: React.ReactNode;
}

export function AlertDialog({ open, onOpenChange, title, description, variant = "default", children }: AlertDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent style={{ maxWidth: "420px" }}>
        <DialogHeader>
          <DialogTitle style={{
            color: (variant === "danger" || variant === "error") ? "hsl(var(--danger-hover))" :
                   (variant === "success") ? "hsl(var(--accent))" :
                   undefined
          }}>
            {title}
          </DialogTitle>
          {description && <DialogDescription>{description}</DialogDescription>}
        </DialogHeader>
        {children}
        <div style={{ display: "flex", justifyContent: "flex-end", marginTop: "1rem" }}>
          <button className="btn btn-secondary" onClick={() => onOpenChange(false)}>OK</button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
