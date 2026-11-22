defmodule RegentsWeb.Techtree.ServiceLive do
  @moduledoc """
  One service's page, from its entry in `RegentsWeb.Techtree.Services`: Skills, Evals,
  Environments and Models under `/techtree/services/<service>`, each with its process
  as numbered steps (a step that runs something carries its status, Tested or
  Planned, beside its name, and one line says what the two words mean), what
  the customer receives, the open-source tools for the project grouped by
  status (a tool that did a part in a published comparison links to its
  result, `Regents.Techtree.Train.Comparisons`), the shared terms and the service's notes, and its price level
  beside the booking action (Models adds its two comparisons, the part only
  its entry carries); Security at `/techtree/services/security`, with its two
  options (a one-off review and monthly monitoring of sites a team proves it
  owns) and the rules monitoring keeps; and Swarm Verify at
  `/techtree/services/swarm-verify`, with the first workflow it covers in five stages,
  the failures it looks for, its three methods as steps (each Tested), the
  public demonstration they ran on, what you receive and the loop after it,
  its limits and the library it is built on.

  Every page ends on Contact: booking a call (`RegentsWeb.Techtree.Components.BookCall`)
  and an email.
  """

  use RegentsWeb, :live_view

  alias RegentsWeb.Techtree.Layouts

  import RegentsWeb.Techtree.Components.Marketing, only: [field: 1, opening: 1, price: 1]

  alias Regents.Techtree.Train.Comparisons
  alias RegentsWeb.Techtree.Components.{BookCall, Enquiry}
  alias RegentsWeb.Techtree.Services

  # What the page says about money beyond the price level and the terms:
  # nothing more.
  @quoted "Quoted on a call."
  @tools_line "Open-source libraries and hosted services for your project, each named with its maker."

  @impl true
  def mount(_params, session, socket) do
    service = Services.fetch!(socket.assigns.live_action)

    {:ok,
     assign(socket,
       page_title: service.name,
       client_key: session["client_tag"],
       service: service,
       mailto: mailto(service),
       quoted: @quoted,
       tools_line: @tools_line,
       comparisons: Comparisons.list(),
       status_line: Services.status_line(),
       terms: Services.terms()
     )}
  end

  # The published comparisons a tool did a part in: as the scorer, the check
  # or the reviser, matched by maker and name.
  defp results(%{maker: maker, name: name}, comparisons) do
    Enum.filter(comparisons, fn comparison ->
      Enum.any?(
        [comparison.scorer, comparison.checker, comparison.reviser],
        &match?(%{maker: ^maker, name: ^name}, &1)
      )
    end)
  end

  defp mailto(service),
    do: "mailto:build@regents.sh?" <> URI.encode_query([subject: service.name], :rfc3986)

  # The page takes no presses; one sent by hand changes nothing.
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def render(%{live_action: :security} = assigns) do
    ~H"""
    <Layouts.page wide flush>
      <.opening
        eyebrow="Services"
        title={@service.name}
        line={@service.promise}
        service="security"
        icon={@service.icon}
        book_call={false}
      >
        <:actions>
          <BookCall.book_call />
          <a class="rg-button rg-button--secondary" href={@mailto}>Email us</a>
        </:actions>
      </.opening>

      <section id="options" class="mk-section" aria-labelledby="options-title">
        <header class="mk-section__head">
          <h2 id="options-title">Options</h2>
        </header>
        <div
          id="options-list"
          class="mk-offer"
          phx-hook="MarketingStagger"
          phx-update="ignore"
        >
          <section
            :for={option <- @service.options}
            id={option.id}
            aria-labelledby={"#{option.id}-title"}
            data-stagger
          >
            <h3 id={"#{option.id}-title"}>{option.name}</h3>
            <p>{option.line}</p>
            <ul>
              <li :for={item <- option.items}>{item}</li>
            </ul>
            <a :if={option[:link]} class="text-link" href={elem(option.link, 1)}>
              {elem(option.link, 0)} <span aria-hidden="true">→</span>
            </a>
          </section>
        </div>
      </section>

      <section class="mk-section mk-split" aria-labelledby="rules-title">
        <header class="mk-section__head">
          <p class="mk-eyebrow">Monitoring</p>
          <h2 id="rules-title">Rules</h2>
        </header>
        <ul id="rules" class="mk-status">
          <li :for={rule <- @service.rules}>{rule}</li>
        </ul>
      </section>

      <.contact service={@service} mailto={@mailto} client_key={@client_key} />
    </Layouts.page>
    """
  end

  def render(%{live_action: :swarm_verify} = assigns) do
    ~H"""
    <Layouts.page wide flush>
      <.opening
        eyebrow="Services"
        title={@service.name}
        line={@service.promise}
        more={@service.more}
        service="swarm-verify"
        icon={@service.icon}
        book_call={false}
      >
        <:actions>
          <BookCall.book_call />
          <a class="rg-button rg-button--secondary" href={@mailto}>Email us</a>
        </:actions>
      </.opening>

      <section id="workflow" class="mk-section" aria-labelledby="workflow-title">
        <header class="mk-section__head">
          <h2 id="workflow-title">Workflow</h2>
          <p>{@service.workflow.line}</p>
        </header>
        <ol
          id="workflow-stages"
          class="mk-sequence mk-sequence--five"
          phx-hook="MarketingStagger"
          phx-update="ignore"
        >
          <li
            :for={{stage, index} <- Enum.with_index(@service.workflow.stages, 1)}
            id={"stage-#{index}"}
            data-stagger
          >
            <span class="mk-sequence__index" aria-hidden="true">
              {String.pad_leading(Integer.to_string(index), 2, "0")}
            </span>
            <h3>{stage.name}</h3>
            <p>{stage.line}</p>
          </li>
        </ol>
      </section>

      <section id="failures" class="mk-section mk-split" aria-labelledby="failures-title">
        <header class="mk-section__head">
          <p class="mk-eyebrow">Workflow</p>
          <h2 id="failures-title">Failures</h2>
        </header>
        <ul class="mk-status mk-status--prose">
          <li :for={failure <- @service.failures}>{failure}</li>
        </ul>
      </section>

      <section id="methods" class="mk-section" aria-labelledby="methods-title">
        <header class="mk-section__head">
          <h2 id="methods-title">Methods</h2>
          <p>{@status_line}</p>
        </header>
        <.steps steps={@service.steps} />
      </section>

      <section id="demonstration" class="mk-section" aria-labelledby="demonstration-title">
        <header class="mk-section__head">
          <p class="mk-eyebrow">Methods</p>
          <h2 id="demonstration-title">Demonstration</h2>
          <p><.words words={@service.demonstration.words} /></p>
          <p class="mk-links">
            <a class="text-link" href={elem(@service.demonstration.link, 1)} rel="noopener">
              {elem(@service.demonstration.link, 0)} <span aria-hidden="true">↗</span>
            </a>
          </p>
        </header>
      </section>

      <section id="receive" class="mk-section mk-split" aria-labelledby="receive-title">
        <header class="mk-section__head">
          <h2 id="receive-title">You receive</h2>
          <p>{@service.loop}</p>
        </header>
        <ul class="mk-status mk-status--prose">
          <li :for={item <- @service.receive}>{item}</li>
        </ul>
      </section>

      <section id="limits" class="mk-section mk-split" aria-labelledby="limits-title">
        <header class="mk-section__head">
          <h2 id="limits-title">Limits</h2>
        </header>
        <ul id="limits-list" class="mk-status">
          <li :for={limit <- @service.limits}>{limit}</li>
        </ul>
      </section>

      <.tools tools={@service.tools} line={@tools_line} comparisons={@comparisons} />

      <.contact service={@service} mailto={@mailto} client_key={@client_key} />
    </Layouts.page>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.page wide flush>
      <.opening
        eyebrow="Services"
        title={@service.name}
        line={@service.promise}
        more={@service[:more]}
        service={Atom.to_string(@service.id)}
        icon={@service.icon}
        book_call={false}
      >
        <:actions>
          <BookCall.book_call />
          <a class="rg-button rg-button--secondary" href={@mailto}>Email us</a>
        </:actions>
        <div class="mk-opening__price" data-entrance-part>
          <.price id="price" level={@service.price} />
          <p>{@quoted}</p>
        </div>
      </.opening>

      <section id="process" class="mk-section" aria-labelledby="process-title">
        <header class="mk-section__head">
          <h2 id="process-title">Process</h2>
          <p>{@status_line}</p>
        </header>
        <.steps steps={@service.steps} />
      </section>

      <section id="receive" class="mk-section mk-split" aria-labelledby="receive-title">
        <header class="mk-section__head">
          <h2 id="receive-title">You receive</h2>
        </header>
        <ul class="mk-status mk-status--prose">
          <li :for={item <- @service.receive}>{item}</li>
        </ul>
      </section>

      <section
        :if={@service[:comparisons]}
        id="comparisons"
        class="mk-section"
        aria-labelledby="comparisons-title"
      >
        <header class="mk-section__head">
          <h2 id="comparisons-title">Comparisons</h2>
          <p>{@service.comparisons.line}</p>
        </header>
        <div class="mk-offer">
          <section
            :for={item <- @service.comparisons.items}
            id={"comparison-#{String.downcase(item.name)}"}
            aria-labelledby={"comparison-#{String.downcase(item.name)}-title"}
          >
            <h3 id={"comparison-#{String.downcase(item.name)}-title"}>{item.name}</h3>
            <p class="mk-offer__question">{item.question}</p>
            <p>{item.answer}</p>
          </section>
        </div>
      </section>

      <.tools tools={@service.tools} line={@tools_line} comparisons={@comparisons} />

      <section id="terms" class="mk-section mk-split" aria-labelledby="terms-title">
        <header class="mk-section__head">
          <h2 id="terms-title">Terms</h2>
        </header>
        <ul class="mk-status mk-status--prose">
          <li :for={term <- @terms}>{term}</li>
        </ul>
      </section>

      <section
        :if={@service.notes != []}
        id="notes"
        class="mk-section mk-split"
        aria-labelledby="notes-title"
      >
        <header class="mk-section__head">
          <h2 id="notes-title">Notes</h2>
        </header>
        <ul class="mk-status mk-status--prose">
          <li :for={note <- @service.notes}><.words words={note} /></li>
        </ul>
      </section>

      <.contact service={@service} mailto={@mailto} client_key={@client_key} />
    </Layouts.page>
    """
  end

  attr :steps, :list, required: true

  # A service's steps in order, one ruled row each: its number, its name with
  # its status where it runs something, and what happens in it.
  defp steps(assigns) do
    ~H"""
    <ol id="steps" class="mk-steps" phx-hook="MarketingStagger" phx-update="ignore">
      <li :for={{step, index} <- Enum.with_index(@steps, 1)} id={"step-#{index}"} data-stagger>
        <span class="mk-steps__index" aria-hidden="true">
          {String.pad_leading(Integer.to_string(index), 2, "0")}
        </span>
        <div class="mk-steps__head">
          <h3>{step.name}</h3>
          <.status_word :if={step.status} status={step.status} />
        </div>
        <p class="mk-steps__words"><.words words={step.words} /></p>
      </li>
    </ol>
    """
  end

  attr :tools, :list, required: true
  attr :line, :string, required: true
  attr :comparisons, :list, required: true

  # The open-source tools for the project, grouped by status, each linked with
  # its maker and its job, and the published results it did a part in.
  defp tools(assigns) do
    ~H"""
    <section id="tools" class="mk-section mk-split" aria-labelledby="tools-title">
      <header class="mk-section__head">
        <h2 id="tools-title">Tools</h2>
        <p>{@line}</p>
      </header>
      <div class="mk-tools__groups">
        <section
          :for={{status, tools} <- Services.by_status(@tools)}
          id={"tools-#{status}"}
          aria-labelledby={"tools-#{status}-title"}
        >
          <h3 id={"tools-#{status}-title"} class="mk-tools__status">
            <.status_word status={status} />
          </h3>
          <dl class="mk-tools">
            <div :for={tool <- tools}>
              <dt>
                <a href={tool.href} class="mk-tools__name">
                  <span class="mk-tools__maker">{tool.maker}’s</span> {tool.name}
                </a>
              </dt>
              <dd>
                {tool.job}
                <span :if={results(tool, @comparisons) != []} class="mk-tools__results">
                  Results:
                  <.link
                    :for={comparison <- results(tool, @comparisons)}
                    navigate={~p"/techtree/train/#{comparison.slug}"}
                    class="text-link"
                  >
                    {comparison.skill.name}
                  </.link>
                </span>
              </dd>
            </div>
          </dl>
        </section>
      </div>
    </section>
    """
  end

  attr :words, :list, required: true

  # A sentence's words and links, run together with no space of their own, so
  # a link sits right against the comma or full stop after it.
  defp words(assigns) do
    ~H"""
    <.word :for={part <- @words} part={part} />
    """
  end

  attr :part, :any, required: true

  defp word(%{part: {text, href}} = assigns) do
    assigns = assign(assigns, text: text, href: href)
    ~H|<a href={@href}>{@text}</a>|
  end

  defp word(assigns), do: ~H|{@part}|

  attr :status, :atom, required: true

  # A status in its one word, quiet beside what it marks: only Delivered takes
  # a colour.
  defp status_word(assigns) do
    ~H"""
    <Regent.Primitives.status
      tone={if(@status == :delivered, do: "success", else: "neutral")}
      class="mk-status-word"
      data-status={@status}
    >
      {Services.status_name(@status)}
    </Regent.Primitives.status>
    """
  end

  attr :service, :map, required: true
  attr :mailto, :string, required: true
  attr :client_key, :any, default: nil

  # The call and the email.
  defp contact(assigns) do
    ~H"""
    <section id="contact" class="mk-band mk-dark mk-contact" aria-labelledby="contact-title">
      <.field id="contact-field" scene="glow" class="mk-band__field" />
      <div class="mk-band__copy">
        <p class="mk-eyebrow">Start</p>
        <h2 id="contact-title">Contact</h2>
        <p class="mk-band__line">{@service.call}</p>
        <div class="mk-band__actions">
          <BookCall.book_call />
          <a class="rg-button rg-button--secondary" href={@mailto}>Email build@regents.sh</a>
        </div>
        <.live_component
          :if={!Regents.read_only?()}
          module={Enquiry}
          id={"service-enquiry-#{@service.id}"}
          service={@service.id}
          client_key={@client_key}
        />
      </div>
    </section>
    """
  end
end
