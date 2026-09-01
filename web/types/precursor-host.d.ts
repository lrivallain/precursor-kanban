/**
 * Ambient types for `@precursor/host` — the Precursor plugin SDK.
 *
 * ## Why this file exists
 *
 * A plugin bundle marks `react`, `react-dom`, both JSX runtimes and
 * `@precursor/host` as **external**. At runtime an import map injected by the
 * host resolves all five to its own `host-runtime.js`, which is what guarantees
 * there is exactly one React on the page. Nothing is ever installed for
 * `@precursor/host`, so there is nothing for TypeScript to resolve either.
 *
 * In the Precursor monorepo the host papered over that with a `paths` mapping
 * onto its own `src/host/runtime.ts`. An out-of-tree plugin has no such source
 * to point at, so it declares the contract instead — which is also the honest
 * thing to do: this is the surface we are *entitled* to, written down, rather
 * than whatever the host's internals happen to expose this week.
 *
 * ## Keeping it honest
 *
 * This mirrors `frontend/src/host/runtime.ts` at **HOST_API_VERSION 2**, and
 * declares only the members this plugin actually imports — a narrower shim is
 * easier to keep true than a complete one.
 *
 * If the host adds something this plugin starts using, widen this file in the
 * same change. If a signature here disagrees with the host, the *host* is
 * right; see CONTRIBUTING.md ("Tracking the host SDK").
 */

declare module "@precursor/host" {
  import type {
    ComponentType,
    CSSProperties,
    ForwardRefExoticComponent,
    MouseEvent as ReactMouseEvent,
    ReactNode,
    RefAttributes,
    TextareaHTMLAttributes,
  } from "react";
  import type { LucideIcon } from "lucide-react";

  /* ---------------------------------------------------------------- */
  /* Contract version                                                  */
  /* ---------------------------------------------------------------- */

  /**
   * Version of the frontend plugin contract. Bumped by the host on any breaking
   * change; the Python side's `precursor.plugin_api.PLUGIN_API_VERSION` is a
   * separate number that moves independently.
   */
  export const HOST_API_VERSION: number;

  /* ---------------------------------------------------------------- */
  /* Read models                                                       */
  /* ---------------------------------------------------------------- */

  export interface IssueLabel {
    name: string;
    /** Hex digits, without the leading `#`. */
    color: string;
  }

  export interface IssueComment {
    id: number;
    user: string;
    body: string;
    created_at?: string | null;
    updated_at: string;
  }

  export interface IssueDetail {
    number: number;
    title: string;
    state: string;
    url: string | null;
    body: string;
    labels: IssueLabel[];
    updated_at: string | null;
    comments: IssueComment[];
    linked_topic_id: number | null;
    linked_topic_title: string | null;
  }

  /**
   * App settings, narrowed to the fields this plugin reads. The host's own
   * `Settings` is much wider; declaring all of it here would be a second copy
   * to keep in sync for no benefit.
   */
  export interface Settings {
    github_repo: string | null;
    issue_associations_enabled: boolean;
  }

  /* ---------------------------------------------------------------- */
  /* Sections                                                          */
  /* ---------------------------------------------------------------- */

  /** Tailwind class tokens for a section's colour scheme. */
  export interface SectionColor {
    /** Icon badge: background tint + icon text colour. */
    icon: string;
    /** Home card border + tint when its start surface is open. */
    activeCard: string;
    /** Home card hover accent (border + tint). */
    hoverCard: string;
    /** Filled primary action button (home "New …"). */
    primaryBtn: string;
    /** Accent text for arrows / hover chrome. */
    accentText: string;
    /** Active tab/rail button: background tint + text colour. */
    activeTab: string;
    /** Rail/tab button hover (inactive). */
    hoverTab: string;
  }

  export interface SectionIconProps {
    size?: number;
    className?: string;
  }

  /** The host services a section gets. Everything core offers goes through it. */
  export interface SectionHost {
    /** Path segments *after* the section root: `/kanban/4-board` → `["4-board"]`. */
    segments: string[];
    /** Current URL hash, without the leading `#` (empty when absent). */
    hash: string;
    /**
     * Rewrite the section-relative URL. `push` adds a history entry; the default
     * replaces it, for state the user didn't explicitly navigate to.
     */
    navigate: (
      segments: string[],
      hash?: string,
      opts?: { push?: boolean },
    ) => void;
    /** Leave the section and open a Precursor topic. */
    openTopic: (topicId: number) => void;
    /** Open the Settings modal, on a plugin's own page when one is named. */
    openSettings: (pluginPageId?: string) => void;
    /** App settings, or `null` while they load. */
    settings: Settings | null;
  }

  export interface SectionPlugin {
    /** Must match the backend descriptor's `id`; also the `/<id>` route. */
    id: string;
    /** Sidebar rail + home card label. */
    label: string;
    icon: ComponentType<SectionIconProps>;
    /** Home card blurb. */
    description: string;
    /** Home card call-to-action, e.g. "Open board". */
    openLabel: string;
    /** Extra command-palette search terms. */
    keywords?: string;
    /** Label for the header "New …" action. Omit for a section with no create flow. */
    newLabel?: string;
    /** What the header "New …" button does. */
    onNew?: (host: SectionHost) => void;
    colors: SectionColor;
    /** `--section-accent` in light / dark, injected as a stylesheet on register. */
    accent: { light: string; dark: string };
    /** Wrapper mounted around the whole app shell while the section is active. */
    Provider?: ComponentType<{ host: SectionHost; children: ReactNode }>;
    /** Rendered in the sidebar body. */
    Sidebar: ComponentType<{ host: SectionHost }>;
    /** Rendered as the main content pane. */
    Main: ComponentType<{ host: SectionHost }>;
    /** Rendered as the header title; falls back to `label`. */
    Title?: ComponentType<{ host: SectionHost }>;
  }

  /**
   * Register a section implementation. Called once at module scope from the
   * plugin's entry file — importing the bundle is what registers it.
   */
  export function registerSection(section: SectionPlugin): void;

  /* ---------------------------------------------------------------- */
  /* HTTP                                                              */
  /* ---------------------------------------------------------------- */

  /**
   * `fetch` with the app's client id, JSON headers and error unwrapping, so a
   * plugin's own endpoints behave exactly like core's.
   */
  export function request<T>(path: string, init?: RequestInit): Promise<T>;

  /** Turn a thrown `request` error into the message the API actually sent. */
  export function apiErrorMessage(e: unknown, fallback?: string): string;

  /**
   * The core API surface, narrowed to what this plugin calls. The host's `api`
   * object is far larger; see the note on `Settings` for why this isn't a full
   * transcription.
   */
  export const api: {
    github: {
      getIssue: (number: number, repo?: string) => Promise<IssueDetail>;
      addIssueComment: (
        number: number,
        body: string,
        repo?: string,
      ) => Promise<IssueComment>;
      setIssueLabels: (
        number: number,
        labels: string[],
        repo?: string,
      ) => Promise<IssueLabel[]>;
      listLabels: (repo?: string) => Promise<IssueLabel[]>;
    };
    plugins: {
      /** A plugin's own settings blob — stored by core, opaque to it. */
      settings: {
        get: (id: string) => Promise<Record<string, unknown>>;
        put: (
          id: string,
          values: Record<string, unknown>,
        ) => Promise<Record<string, unknown>>;
      };
    };
  };

  /* ---------------------------------------------------------------- */
  /* Shared chrome                                                     */
  /* ---------------------------------------------------------------- */

  export interface ModalProps {
    /** Dismiss handler, invoked on backdrop click and Escape (when enabled). */
    onClose?: () => void;
    children: ReactNode;
    /** Class list for the centered panel (width, background, border, padding). */
    panelClassName?: string;
    /** Inline style for the centered panel (e.g. an explicit resizable size). */
    panelStyle?: CSSProperties;
    /** Backdrop tint utility. Defaults to a translucent black scrim. */
    backdropClassName?: string;
    /** Stacking tier from the host's shared Z_INDEX scale. */
    zIndex?: string;
    /** Pad around the panel so it never touches the viewport edge. */
    padded?: boolean;
    /** Close when the backdrop is clicked. Default true. */
    closeOnBackdrop?: boolean;
    /** Close when Escape is pressed. Default false. */
    closeOnEscape?: boolean;
    role?: "dialog" | "alertdialog";
    labelledBy?: string;
    describedBy?: string;
  }

  /** Backdrop + centered panel shell shared by the app's modals. */
  export function Modal(props: ModalProps): ReactNode;

  /** The app's Markdown renderer, with the same plugins and styling. */
  export function Markdown(props: {
    children: string;
    className?: string;
  }): ReactNode;

  /** Centered placeholder with the app logo, for empty and loading states. */
  export function EmptyHero(props: { label: string }): ReactNode;

  /** A GitHub label, rendered in its own colour. */
  export function IssueLabelChip(props: { label: IssueLabel }): ReactNode;

  /** Open/closed pill for an issue. */
  export function IssueStateBadge(props: { state: string }): ReactNode;

  export interface RefineTextareaProps
    extends Omit<
      TextareaHTMLAttributes<HTMLTextAreaElement>,
      "value" | "onChange"
    > {
    value: string;
    onValueChange: (value: string) => void;
    /** Context hint sent to the backend (e.g. "system_prompt", "note"). */
    refineKind?: string;
    /** Optional freeform steer for the rewrite. */
    refineInstruction?: string;
    /** Classes for the relative wrapper (e.g. "h-full"). */
    containerClassName?: string;
    /** Opt into Markdown affordances: a formatting toolbar plus shortcuts. */
    markdown?: boolean;
  }

  /** A textarea with a built-in "Refine with AI" affordance. */
  export const RefineTextarea: ForwardRefExoticComponent<
    RefineTextareaProps & RefAttributes<HTMLTextAreaElement>
  >;

  export interface ContextMenuSubItem {
    label: string;
    onSelect: () => void | Promise<void>;
    /** Full Tailwind class for a small leading dot. */
    dot?: string;
    checked?: boolean;
  }

  export interface ContextMenuItem {
    label: string;
    icon: LucideIcon;
    onSelect?: () => void | Promise<void>;
    danger?: boolean;
    /** Nested choices. When present the row opens a flyout instead of acting. */
    submenu?: ContextMenuSubItem[];
  }

  /** The app's right-click menu: same portal, clamping and dismissal as core's. */
  export function ContextMenu(props: {
    x: number;
    y: number;
    label: string;
    items: ContextMenuItem[];
    onClose: () => void;
  }): ReactNode;

  export interface ConfirmOptions {
    title?: string;
    message: string;
    confirmLabel?: string;
    cancelLabel?: string;
    variant?: "default" | "warning" | "danger";
  }

  /** The app-wide confirm dialog, for a plugin's destructive actions. */
  export function useConfirm(): (options: ConfirmOptions) => Promise<boolean>;

  /**
   * Scroll the active row of a list into view when the selection changes.
   * Attach the returned ref only to the active element.
   */
  export function useScrollActiveIntoView<T extends HTMLElement = HTMLElement>(
    activeKey: string | number | null | undefined,
  ): (el: T | null) => void;

  /** Two-axis resizable panel with a corner grip, persisted to localStorage. */
  export function useResizableBox(options: {
    storageKey: string;
    defaultWidth: number;
    defaultHeight: number;
    minWidth: number;
    minHeight: number;
    /** Upper bounds default to the viewport (recomputed on each drag). */
    maxWidth?: number;
    maxHeight?: number;
  }): {
    size: { width: number; height: number };
    onResizeStart: (e: ReactMouseEvent) => void;
  };
}
