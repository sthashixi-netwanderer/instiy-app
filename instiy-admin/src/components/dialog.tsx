import * as React from "react";
import * as DialogPrimitive from "@radix-ui/react-dialog";
import { X } from "lucide-react";

const Dialog = DialogPrimitive.Root;
const DialogTrigger = DialogPrimitive.Trigger;
const DialogPortal = DialogPrimitive.Portal;
const DialogClose = DialogPrimitive.Close;

const DialogOverlay = React.forwardRef<
	React.ComponentRef<typeof DialogPrimitive.Overlay>,
	React.ComponentPropsWithoutRef<typeof DialogPrimitive.Overlay>
>(({ className, style, ...props }, ref) => (
	<DialogPrimitive.Overlay
		ref={ref}
		style={{
			position: "fixed",
			top: 0,
			left: 0,
			right: 0,
			bottom: 0,
			zIndex: 1000,
			background: "rgba(0, 0, 0, 0.55)",
			display: "flex",
			alignItems: "center",
			justifyContent: "center",
			...(typeof style === "object" ? style : {}),
		}}
		{...props}
	/>
));
DialogOverlay.displayName = DialogPrimitive.Overlay.displayName;

const DialogContent = React.forwardRef<
	React.ComponentRef<typeof DialogPrimitive.Content>,
	React.ComponentPropsWithoutRef<typeof DialogPrimitive.Content>
>(({ className, children, style, ...props }, ref) => (
	<DialogPortal>
		<DialogOverlay />
		<DialogPrimitive.Content
			ref={ref}
			style={{
				position: "fixed",
				left: "50%",
				top: "50%",
				transform: "translate(-50%, -50%)",
				backgroundColor: "hsl(var(--bg-card))",
				border: "1px solid hsl(var(--border))",
				borderRadius: "var(--radius-md)",
				padding: "1.5rem",
				width: "90%",
				maxWidth: "500px",
				maxHeight: "90vh",
				overflowY: "auto",
				boxShadow: "var(--shadow-lg)",
				zIndex: 1001,
				outline: "none",
				...(typeof style === "object" ? style : {}),
			}}
			{...props}
		>
			{children}
			<DialogPrimitive.Close
				style={{
					position: "absolute",
					right: "1rem",
					top: "1rem",
					background: "none",
					border: "none",
					cursor: "pointer",
					color: "hsl(var(--text-secondary))",
					padding: "4px",
					display: "flex",
					alignItems: "center",
					justifyContent: "center",
				}}
			>
				<X size={18} />
			</DialogPrimitive.Close>
		</DialogPrimitive.Content>
	</DialogPortal>
));
DialogContent.displayName = DialogPrimitive.Content.displayName;

const DialogHeader = ({
	className,
	style,
	...props
}: React.HTMLAttributes<HTMLDivElement>) => (
	<div
		style={{
			display: "flex",
			flexDirection: "column",
			gap: "0.375rem",
			textAlign: "center",
			...(typeof style === "object" ? style : {}),
		}}
		{...props}
	/>
);
DialogHeader.displayName = "DialogHeader";

const DialogFooter = ({
	className,
	style,
	...props
}: React.HTMLAttributes<HTMLDivElement>) => (
	<div
		style={{
			display: "flex",
			flexDirection: "row",
			justifyContent: "flex-end",
			gap: "0.625rem",
			marginTop: "1rem",
			...(typeof style === "object" ? style : {}),
		}}
		{...props}
	/>
);
DialogFooter.displayName = "DialogFooter";

const DialogTitle = React.forwardRef<
	React.ComponentRef<typeof DialogPrimitive.Title>,
	React.ComponentPropsWithoutRef<typeof DialogPrimitive.Title>
>(({ className, style, ...props }, ref) => (
	<DialogPrimitive.Title
		ref={ref}
		style={{
			fontSize: "1.1rem",
			fontFamily: "var(--font-title)",
			lineHeight: 1.4,
			...(typeof style === "object" ? style : {}),
		}}
		{...props}
	/>
));
DialogTitle.displayName = DialogPrimitive.Title.displayName;

const DialogDescription = React.forwardRef<
	React.ComponentRef<typeof DialogPrimitive.Description>,
	React.ComponentPropsWithoutRef<typeof DialogPrimitive.Description>
>(({ className, style, ...props }, ref) => (
	<DialogPrimitive.Description
		ref={ref}
		style={{
			fontSize: "0.85rem",
			color: "hsl(var(--text-secondary))",
			lineHeight: 1.5,
			...(typeof style === "object" ? style : {}),
		}}
		{...props}
	/>
));
DialogDescription.displayName = DialogPrimitive.Description.displayName;

export {
	Dialog,
	DialogPortal,
	DialogOverlay,
	DialogTrigger,
	DialogClose,
	DialogContent,
	DialogHeader,
	DialogFooter,
	DialogTitle,
	DialogDescription,
};
