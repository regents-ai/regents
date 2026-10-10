defmodule RegentsWeb.ArticleEditor do
  @moduledoc "Creates an article using the current verified admin session."
  use RegentsWeb, :live_component

  alias Regent.Primitives, as: P
  alias RegentsWeb.FormErrors

  @max_authors 20
  @fields ~w(title date authors markdown cover_alt)

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> RegentsWeb.Live.Session.check_component_events(&take_account/2)
     |> attach_hook(:article_admin, :handle_event, fn _, _, socket ->
       if socket.assigns.lease && Regents.Blog.admin?(socket.assigns.account) &&
            RegentsWeb.Plugs.LaunchGate.app_surfaces_enabled?() do
         {:cont, socket}
       else
         {:halt, %{},
          assign(socket,
            form: nil,
            notice: "Your editor access has ended. Reload and sign in again."
          )}
       end
     end)
     |> allow_upload(:cover,
       accept: ~w(.png .jpg .jpeg .webp),
       max_entries: 1,
       max_file_size: 1_000_000,
       auto_upload: true
     )
     |> assign(form: nil, cover: nil, cover_name: nil, notice: nil, saved: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(Map.take(assigns, [:id, :lease])) |> take_account(assigns.account)}
  end

  defp take_account(socket, account) do
    socket = assign(socket, account: account)

    if socket.assigns.form == nil and Regents.Blog.admin?(account) do
      params = %{
        "date" => Date.to_iso8601(Date.utc_today()),
        "authors" => [%{"name" => "", "x" => ""}]
      }

      assign(socket, form: form(account, params))
    else
      socket
    end
  end

  defp form(account, params) do
    Regents.Blog.Post
    |> AshPhoenix.Form.for_create(:publish,
      actor: %Regents.Actors.Human{human_account_id: account.id},
      as: "article",
      params: params
    )
    |> to_form()
  end

  @impl true
  def handle_event("validate", %{"article" => params}, socket) do
    params = clean(params) |> Map.put("cover", socket.assigns.cover)

    {:noreply,
     assign(socket,
       form:
         form(socket.assigns.account, params)
         |> AshPhoenix.Form.validate(params)
         |> to_form(),
       notice: nil
     )}
  end

  def handle_event("add_author", _params, socket) do
    params = socket.assigns.form.params
    authors = author_rows(params)

    if length(authors) < @max_authors do
      params = Map.put(params, "authors", authors ++ [%{"name" => "", "x" => ""}])
      {:noreply, assign(socket, form: form(socket.assigns.account, params))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_author", %{"index" => index}, socket) do
    params = socket.assigns.form.params
    authors = author_rows(params)

    case Integer.parse(index) do
      {index, ""} when index >= 0 and index < length(authors) and length(authors) > 1 ->
        {:noreply,
         assign(socket,
           form:
             form(
               socket.assigns.account,
               Map.put(params, "authors", List.delete_at(authors, index))
             )
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_cover", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :cover, ref)}

  def handle_event("publish", %{"article" => params}, socket) do
    {complete, incomplete} = uploaded_entries(socket, :cover)

    errors =
      upload_errors(socket.assigns.uploads.cover) ++
        Enum.flat_map(
          socket.assigns.uploads.cover.entries,
          &upload_errors(socket.assigns.uploads.cover, &1)
        )

    if incomplete != [] or errors != [] do
      notice =
        if errors == [],
          do: "Wait for the cover image to finish uploading.",
          else: "Remove the invalid cover and choose a PNG, JPEG or WebP image up to 1 MB."

      {:noreply, assign(socket, notice: notice)}
    else
      socket =
        if complete != [] do
          [{cover, name}] =
            consume_uploaded_entries(socket, :cover, fn %{path: path}, entry ->
              {:ok, {File.read!(path), entry.client_name}}
            end)

          assign(socket, cover: cover, cover_name: name)
        else
          socket
        end

      params = clean(params) |> Map.put("cover", socket.assigns.cover)

      case AshPhoenix.Form.submit(form(socket.assigns.account, params), params: params) do
        {:ok, post} ->
          {:noreply, assign(socket, form: nil, saved: post, notice: nil, cover: nil)}

        {:error, form} ->
          {:noreply,
           assign(socket,
             form: to_form(form),
             notice: "The article wasn't published. Check the fields below."
           )}
      end
    end
  end

  defp clean(params) do
    params |> Map.take(@fields) |> Map.put("authors", author_rows(params))
  end

  defp author_rows(params) do
    rows =
      case Map.get(params, "authors", []) do
        rows when is_list(rows) ->
          rows

        rows when is_map(rows) ->
          rows
          |> Enum.flat_map(fn
            {index, row} when is_binary(index) ->
              case Integer.parse(index) do
                {number, ""} when number >= 0 -> [{number, row}]
                _ -> []
              end

            _ ->
              []
          end)
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.map(&elem(&1, 1))

        _ ->
          []
      end

    rows
    |> Enum.take(@max_authors + 1)
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn row ->
      Map.new(~w(name x), fn key ->
        value = Map.get(row, key, Map.get(row, String.to_existing_atom(key), ""))
        {key, if(is_binary(value), do: value, else: "")}
      end)
    end)
  end

  defp value(form, field), do: form[field].value || ""

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, authors: if(assigns.form, do: author_rows(assigns.form.params), else: []))

    ~H"""
    <article id={@id} class="account-page article-editor">
      <header class="account-heading">
        <p class="account-kicker">Articles</p>
        <h1 tabindex="-1">New Article</h1>
        <p class="account-lede">Write in Markdown, add your authors and cover, then publish.</p>
        <.link patch="/articles">← Back to Articles</.link>
      </header>
      <P.notice :if={@notice} tone="error" role="alert">{@notice}</P.notice>
      <section :if={@saved} class="account-panel" role="status">
        <h2>Article saved</h2>
        <p :if={Date.compare(@saved.date, Date.utc_today()) == :gt}>
          It will appear on {Calendar.strftime(@saved.date, "%B %-d, %Y")} (UTC).
        </p>
        <.link
          :if={Date.compare(@saved.date, Date.utc_today()) != :gt}
          class="rg-button"
          href={"/articles/#{@saved.slug}"}
        >View Article →</.link>
        <.link href="/admin/articles">Write another article</.link>
      </section>
      <.form
        :if={@form && !@saved}
        for={@form}
        id="new-article-form"
        class="account-panel article-editor__form"
        phx-change="validate"
        phx-submit="publish"
        phx-target={@myself}
      >
        <P.field
          :let={field}
          id="article-title"
          label="Title"
          errors={FormErrors.messages(@form[:title])}
        >
          <input
            id={field.id}
            name={@form[:title].name}
            value={value(@form, :title)}
            maxlength="240"
            required
            aria-invalid={field.aria_invalid}
            aria-describedby={field.described_by}
          />
        </P.field>
        <P.field
          :let={field}
          id="article-date"
          label="Publication date"
          errors={FormErrors.messages(@form[:date])}
        >
          <input
            id={field.id}
            type="date"
            name={@form[:date].name}
            value={value(@form, :date)}
            required
            aria-invalid={field.aria_invalid}
            aria-describedby={field.described_by}
          />
        </P.field>
        <fieldset class="article-editor__authors">
          <legend>Authors</legend>
          <div :for={{author, index} <- Enum.with_index(@authors)} class="article-editor__author">
            <P.field :let={field} id={"article-author-#{index}"} label={"Author #{index + 1}"}>
              <input
                id={field.id}
                name={"article[authors][#{index}][name]"}
                value={Map.get(author, "name", Map.get(author, :name, ""))}
                required
                maxlength="120"
              />
            </P.field>
            <P.field :let={field} id={"article-author-x-#{index}"} label="X account">
              <input
                id={field.id}
                name={"article[authors][#{index}][x]"}
                value={Map.get(author, "x", Map.get(author, :x, ""))}
                placeholder="@your_handle"
                required
                maxlength="128"
              />
            </P.field>
            <P.button
              :if={length(@authors) > 1}
              type="button"
              variant="quiet"
              phx-click="remove_author"
              phx-value-index={index}
              phx-target={@myself}
              aria-label={"Remove author #{index + 1}"}
            >Remove</P.button>
          </div>
          <p :for={error <- FormErrors.messages(@form[:authors])} class="rg-field-errors" role="alert">
            {error}
          </p>
          <P.button
            type="button"
            variant="secondary"
            phx-click="add_author"
            phx-target={@myself}
            disabled={length(@authors) >= 20}
          >Add author</P.button>
        </fieldset>
        <P.field
          :let={field}
          id="article-markdown"
          label="Markdown text"
          errors={FormErrors.messages(@form[:markdown])}
        >
          <textarea
            id={field.id}
            name={@form[:markdown].name}
            rows="20"
            required
            maxlength="1000000"
            spellcheck="true"
            aria-invalid={field.aria_invalid}
            aria-describedby={field.described_by}
          >{value(@form, :markdown)}</textarea>
        </P.field>
        <section class="article-editor__cover" aria-labelledby="article-cover-label">
          <h2 id="article-cover-label">Cover image</h2>
          <p>PNG, JPEG or WebP. Maximum 1 MB.</p>
          <label for={@uploads.cover.ref}>Choose cover image</label>
          <.live_file_input upload={@uploads.cover} />
          <p :if={@cover_name}>Selected: {@cover_name}</p>
          <div :for={entry <- @uploads.cover.entries}>
            <.live_img_preview entry={entry} />
            <p>{entry.client_name} · {entry.progress}% uploaded</p>
            <P.button
              type="button"
              variant="quiet"
              phx-click="cancel_cover"
              phx-value-ref={entry.ref}
              phx-target={@myself}
            >Remove cover</P.button>
            <p :for={error <- upload_errors(@uploads.cover, entry)} role="alert">
              {upload_error(error)}
            </p>
          </div>
          <p :for={error <- upload_errors(@uploads.cover)} role="alert">{upload_error(error)}</p>
          <p
            :for={
              error <-
                if(@uploads.cover.entries == [] and (@notice || @cover),
                  do: FormErrors.messages(@form[:cover]),
                  else: []
                )
            }
            role="alert"
          >
            {error}
          </p>
        </section>
        <P.field
          :let={field}
          id="article-cover-alt"
          label="Cover description (optional)"
          errors={FormErrors.messages(@form[:cover_alt])}
        >
          <input
            id={field.id}
            name={@form[:cover_alt].name}
            value={value(@form, :cover_alt)}
            placeholder="Describe what the image shows"
            maxlength="500"
          />
        </P.field>
        <P.button type="submit" phx-disable-with="Publishing…">Publish Article →</P.button>
      </.form>
    </article>
    """
  end

  defp upload_error(:too_large), do: "The image must be 1 MB or smaller."
  defp upload_error(:not_accepted), do: "Choose a PNG, JPEG or WebP image."
  defp upload_error(:too_many_files), do: "Choose one cover image."
  defp upload_error(_), do: "The image couldn't upload. Try again."
end
