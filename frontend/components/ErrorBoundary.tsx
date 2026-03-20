"use client";

import { Component, type ReactNode } from "react";

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  message: string;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, message: "" };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, message: error.message };
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback ?? (
        <div className="border border-warning/30 bg-warning/5 p-6 rounded-none">
          <p className="mb-1 font-body text-[13px] text-warning">⚠ Something went wrong</p>
          <p className="font-body text-[11px] text-text-muted">{this.state.message}</p>
        </div>
      );
    }

    return this.props.children;
  }
}