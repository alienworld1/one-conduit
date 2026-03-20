"use client";

import { useState } from "react";
import type { ReactNode } from "react";

type CodeBlockProps = {
  code: string;
  language?: "typescript" | "bash" | "solidity";
  filename?: string;
};

const KEYWORD_PATTERN =
  /\b(const|let|await|async|import|from|export|default|function|return|true|false|type|interface)\b/g;
const STRING_PATTERN = /("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`|0x[0-9a-fA-F]+)/g;

export function CodeBlock({ code, language, filename }: CodeBlockProps) {
  const [copied, setCopied] = useState(false);

  function handleCopy() {
    navigator.clipboard
      .writeText(code)
      .then(() => {
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      })
      .catch(() => {
        setCopied(false);
      });
  }

  return (
    <div className="mb-6 overflow-hidden rounded-none border border-border bg-surface-2">
      <div className="flex items-center justify-between border-b border-border px-4 py-2">
        <span className="font-data text-[11px] tracking-widest text-text-muted uppercase">
          {filename ?? language ?? "code"}
        </span>
        <button
          type="button"
          onClick={handleCopy}
          className="font-body text-[11px] text-text-muted transition-colors duration-120 hover:text-text-secondary"
        >
          {copied ? "COPIED" : "COPY"}
        </button>
      </div>
      <pre className="overflow-x-auto px-4 py-4">
        <code className="font-data text-[13px] leading-[1.7] text-text-primary">
          <HighlightedCode code={code} language={language} />
        </code>
      </pre>
    </div>
  );
}

function HighlightedCode({ code, language }: { code: string; language?: string }) {
  const lines = code.split("\n");

  if (language === "bash") {
    return (
      <>
        {lines.map((line, index) => (
          <span key={`bash-${index}`}>
            {applyBashHighlight(line)}
            {index < lines.length - 1 ? "\n" : null}
          </span>
        ))}
      </>
    );
  }

  return (
    <>
      {lines.map((line, index) => (
        <span key={`line-${index}`}>
          {tokeniseLine(line)}
          {index < lines.length - 1 ? "\n" : null}
        </span>
      ))}
    </>
  );
}

function tokeniseLine(line: string): ReactNode {
  if (line.trimStart().startsWith("//")) {
    return <span className="text-text-muted">{line}</span>;
  }

  const commentIndex = line.indexOf("//");
  const codeChunk = commentIndex >= 0 ? line.slice(0, commentIndex) : line;
  const commentChunk = commentIndex >= 0 ? line.slice(commentIndex) : "";

  const tokens: ReactNode[] = [];
  let lastIndex = 0;
  let match: RegExpExecArray | null;

  STRING_PATTERN.lastIndex = 0;
  while ((match = STRING_PATTERN.exec(codeChunk)) !== null) {
    const before = codeChunk.slice(lastIndex, match.index);
    if (before) {
      tokens.push(...highlightKeywords(before));
    }

    tokens.push(
      <span key={`str-${match.index}`} className="text-yield">
        {match[0]}
      </span>,
    );

    lastIndex = match.index + match[0].length;
  }

  const tail = codeChunk.slice(lastIndex);
  if (tail) {
    tokens.push(...highlightKeywords(tail));
  }

  if (commentChunk) {
    tokens.push(
      <span key="inline-comment" className="text-text-muted">
        {commentChunk}
      </span>,
    );
  }

  return <>{tokens}</>;
}

function highlightKeywords(text: string): ReactNode[] {
  const segments = text.split(KEYWORD_PATTERN);

  return segments.map((segment, index) => {
    if (segment.match(KEYWORD_PATTERN)) {
      return (
        <span key={`kw-${index}`} className="text-accent">
          {segment}
        </span>
      );
    }

    return <span key={`txt-${index}`}>{segment}</span>;
  });
}

function applyBashHighlight(line: string): ReactNode {
  const trimmed = line.trimStart();
  if (trimmed.startsWith("#")) {
    return <span className="text-text-muted">{line}</span>;
  }

  const commentIndex = line.indexOf("#");
  const command = commentIndex >= 0 ? line.slice(0, commentIndex) : line;
  const comment = commentIndex >= 0 ? line.slice(commentIndex) : "";

  return (
    <>
      <span className="text-text-primary">{command}</span>
      {comment ? <span className="text-text-muted">{comment}</span> : null}
    </>
  );
}
