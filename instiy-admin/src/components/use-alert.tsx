import { useState, useCallback } from "react";
import { AlertDialog } from "./alert-dialog";
import { ConfirmDialog } from "./confirm-dialog";

// useAlert hook
interface AlertState {
  open: boolean;
  title: string;
  description?: string;
  variant?: "default" | "danger" | "success" | "error" | "info";
}

export function useAlert() {
  const [state, setState] = useState<AlertState>({ open: false, title: "" });

  const showAlert = useCallback((title: string, descriptionOrOpts?: string | { description?: string; variant?: "default" | "danger" | "success" | "error" | "info" }, variant?: "default" | "danger" | "success" | "error" | "info") => {
    if (typeof descriptionOrOpts === "string") {
      setState({ open: true, title, description: descriptionOrOpts, variant: variant });
    } else {
      setState({ open: true, title, description: descriptionOrOpts?.description, variant: descriptionOrOpts?.variant });
    }
  }, []);

  const AlertComponent = (
    <AlertDialog
      open={state.open}
      onOpenChange={(open) => setState(s => ({ ...s, open }))}
      title={state.title}
      description={state.description}
      variant={state.variant}
    />
  );

  return { alert: showAlert, showAlert, AlertComponent };
}

// useConfirm hook
interface ConfirmState {
  open: boolean;
  title: string;
  description?: string;
  variant?: "default" | "danger";
  confirmLabel?: string;
  onConfirm: () => void | Promise<void>;
}

export function useConfirm() {
  const [state, setState] = useState<ConfirmState>({
    open: false,
    title: "",
    onConfirm: () => {},
  });
  const [confirmLoading, setConfirmLoading] = useState(false);

  const showConfirm = useCallback((
    title: string,
    descriptionOrOnConfirm: string | (() => void | Promise<void>),
    onConfirmOrOpts?: (() => void | Promise<void>) | { description?: string; variant?: "default" | "danger"; confirmLabel?: string },
    opts?: { variant?: "default" | "danger"; confirmLabel?: string }
  ) => {
    if (typeof descriptionOrOnConfirm === "function") {
      const onConfirm = descriptionOrOnConfirm;
      const options = onConfirmOrOpts as { description?: string; variant?: "default" | "danger"; confirmLabel?: string } | undefined;
      setState({
        open: true,
        title,
        description: options?.description,
        onConfirm,
        variant: options?.variant,
        confirmLabel: options?.confirmLabel,
      });
    } else {
      const description = descriptionOrOnConfirm;
      const onConfirm = onConfirmOrOpts as () => void | Promise<void>;
      setState({
        open: true,
        title,
        description,
        onConfirm,
        variant: opts?.variant,
        confirmLabel: opts?.confirmLabel,
      });
    }
  }, []);

  const ConfirmComponent = (
    <ConfirmDialog
      open={state.open}
      onOpenChange={(open) => setState(s => ({ ...s, open }))}
      title={state.title}
      description={state.description}
      variant={state.variant}
      confirmLabel={state.confirmLabel}
      onConfirm={state.onConfirm}
      loading={confirmLoading}
    />
  );

  return { confirm: showConfirm, showConfirm, confirmLoading, setConfirmLoading, ConfirmComponent };
}
