defmodule LiveMetricsWeb.Components.ConfirmDialog do
  @moduledoc """
  Confirmation dialog for destructive actions.

  Render it conditionally from the LiveView state:

      <ConfirmDialog.confirm_dialog
        :if={@deleting}
        id="delete-recipe-dialog"
        title="Delete recipe?"
        on_confirm="delete_recipe"
        on_cancel="cancel_delete"
      >
        This can not be undone.
      </ConfirmDialog.confirm_dialog>

  Set `blocked` to explain why the action is not possible: only the close button is shown.
  """
  use LiveMetricsWeb, :html

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :on_confirm, :string, required: true, doc: "event sent when the user confirms"
  attr :on_cancel, :string, required: true, doc: "event sent on cancel, backdrop click or Escape"
  attr :confirm_label, :string, default: "Delete"
  attr :blocked, :boolean, default: false, doc: "hide the confirm button"
  slot :inner_block, required: true

  def confirm_dialog(assigns) do
    ~H"""
    <dialog
      id={@id}
      class="modal modal-open"
      role="alertdialog"
      aria-labelledby={"#{@id}-title"}
      phx-window-keydown={@on_cancel}
      phx-key="escape"
    >
      <div class="modal-box max-w-md">
        <div class="flex items-start gap-4">
          <div class={[
            "flex h-10 w-10 shrink-0 items-center justify-center rounded-full",
            if(@blocked, do: "bg-warning/15 text-warning", else: "bg-error/15 text-error")
          ]}>
            <.icon
              name={if(@blocked, do: "hero-no-symbol", else: "hero-exclamation-triangle")}
              class="w-5 h-5"
            />
          </div>
          <div class="space-y-2">
            <h3 id={"#{@id}-title"} class="font-bold text-lg">{@title}</h3>
            <div class="text-sm text-base-content/70 space-y-2">{render_slot(@inner_block)}</div>
          </div>
        </div>

        <div class="modal-action">
          <.button
            id={"#{@id}-cancel"}
            type="button"
            class="btn btn-ghost"
            phx-click={@on_cancel}
          >
            {if @blocked, do: "Close", else: "Cancel"}
          </.button>
          <.button
            :if={!@blocked}
            id={"#{@id}-confirm"}
            type="button"
            class="btn btn-error"
            phx-click={@on_confirm}
            phx-disable-with="Deleting…"
          >
            <.icon name="hero-trash" class="w-4 h-4" /> {@confirm_label}
          </.button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click={@on_cancel}></div>
    </dialog>
    """
  end
end
