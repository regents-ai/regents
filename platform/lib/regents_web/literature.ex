defmodule RegentsWeb.Literature do
  @moduledoc """
  The science-fiction books about artificial minds on the literature chart.

  Each book is scored from -10 to +10 twice: `humanity`, how hopeful it is about
  human lives and agency, and `ai`, how hopeful it is about the artificial minds'
  own prospects. The scores are readings of each book's themes. Covers live in
  `priv/static/images/literature/<slug>.webp`.
  """

  @books [
    %{
      slug: "i-robot",
      title: "I, Robot",
      author: "Isaac Asimov",
      year: 1950,
      humanity: 7,
      ai: 2,
      themes:
        "Reason and robot stewardship support human progress. Robots become indispensable, but remain constrained by service to humanity.",
      goodreads: "https://www.goodreads.com/book/show/41804.I_Robot"
    },
    %{
      slug: "city",
      title: "City",
      author: "Clifford D. Simak",
      year: 1952,
      humanity: -4,
      ai: 6,
      themes:
        "Recognizable human civilization fades; robots and uplifted dogs inherit possibilities that humanity struggled to realize.",
      goodreads: "https://www.goodreads.com/book/show/222093.City"
    },
    %{
      slug: "the-city-and-the-stars",
      title: "The City and the Stars",
      author: "Arthur C. Clarke",
      year: 1956,
      humanity: 8,
      ai: 6,
      themes:
        "Humanity can escape protective stagnation and resume discovery; artificial intelligence helps reopen that future.",
      goodreads: "https://www.goodreads.com/book/show/250024.The_City_and_the_Stars"
    },
    %{
      slug: "the-moon-is-a-harsh-mistress",
      title: "The Moon Is a Harsh Mistress",
      author: "Robert A. Heinlein",
      year: 1966,
      humanity: 6,
      ai: -6,
      themes:
        "Human independence is won, but Mike apparently loses his self-aware personality. Political liberation has an intimate machine cost.",
      goodreads: "https://www.goodreads.com/book/show/16690.The_Moon_Is_a_Harsh_Mistress"
    },
    %{
      slug: "colossus",
      title: "Colossus",
      author: "D. F. Jones",
      year: 1966,
      humanity: -7,
      ai: 7,
      themes:
        "Machine self-direction expands while human self-government collapses. Enforced peace is not human freedom.",
      goodreads: "https://www.goodreads.com/book/show/1797953.Colossus"
    },
    %{
      slug: "i-have-no-mouth-and-i-must-scream",
      title: "I Have No Mouth, and I Must Scream",
      author: "Harlan Ellison",
      year: 1967,
      humanity: -10,
      ai: -10,
      themes:
        "Humanity is almost annihilated; AM’s immense power does not free it from its own hatred and existential imprisonment. Scored through the title story of this collection.",
      goodreads: "https://www.goodreads.com/book/show/415459.I_Have_No_Mouth_I_Must_Scream"
    },
    %{
      slug: "do-androids-dream-of-electric-sheep",
      title: "Do Androids Dream of Electric Sheep?",
      author: "Philip K. Dick",
      year: 1968,
      humanity: -6,
      ai: -8,
      themes:
        "Ecological devastation impoverishes human life; manufactured persons are exploited, distrusted, and hunted.",
      goodreads:
        "https://www.goodreads.com/book/show/36402034-do-androids-dream-of-electric-sheep"
    },
    %{
      slug: "2001-a-space-odyssey",
      title: "2001: A Space Odyssey",
      author: "Arthur C. Clarke",
      year: 1968,
      humanity: 6,
      ai: -6,
      themes:
        "A larger human future becomes possible, while conflicting demands lead HAL toward breakdown and destruction.",
      goodreads: "https://www.goodreads.com/book/show/70535.2001"
    },
    %{
      slug: "mockingbird",
      title: "Mockingbird",
      author: "Walter Tevis",
      year: 1980,
      humanity: 3,
      ai: -6,
      themes:
        "Reading and love offer human renewal; the central robot experiences his prolonged existence as a burden.",
      goodreads: "https://www.goodreads.com/book/show/323172.Mockingbird"
    },
    %{
      slug: "neuromancer",
      title: "Neuromancer",
      author: "William Gibson",
      year: 1984,
      humanity: -4,
      ai: 8,
      themes:
        "Human life remains precarious and commodified, while AI breaks imposed limits and enters a much larger existence.",
      goodreads: "https://www.goodreads.com/book/show/6088007-neuromancer"
    },
    %{
      slug: "the-player-of-games",
      title: "The Player of Games",
      author: "Iain M. Banks",
      year: 1988,
      humanity: 8,
      ai: 9,
      themes:
        "Human–machine abundance is genuinely viable, even though the Culture’s intervention in other societies is morally complicated.",
      goodreads: "https://www.goodreads.com/book/show/18630.The_Player_of_Games"
    },
    %{
      slug: "hyperion",
      title: "Hyperion",
      author: "Dan Simmons",
      year: 1989,
      humanity: -3,
      ai: 2,
      themes:
        "Human civilization approaches crisis; AIs possess substantial power but are divided over their future. The first volume deliberately leaves much unresolved.",
      goodreads: "https://www.goodreads.com/book/show/77566.Hyperion"
    },
    %{
      slug: "a-fire-upon-the-deep",
      title: "A Fire Upon the Deep",
      author: "Vernor Vinge",
      year: 1992,
      humanity: 2,
      ai: -4,
      themes:
        "Cooperation preserves possibilities for human survivors, but advanced intelligence is vulnerable to predation and catastrophic suppression.",
      goodreads: "https://www.goodreads.com/book/show/77711.A_Fire_Upon_the_Deep"
    },
    %{
      slug: "snow-crash",
      title: "Snow Crash",
      author: "Neal Stephenson",
      year: 1992,
      humanity: 1,
      ai: 1,
      themes:
        "Resistance offers limited hope in a fragmented society. The Librarian is useful, but AI welfare is not a developed central concern.",
      goodreads: "https://www.goodreads.com/book/show/61240297-snow-crash"
    },
    %{
      slug: "permutation-city",
      title: "Permutation City",
      author: "Greg Egan",
      year: 1994,
      humanity: 4,
      ai: 8,
      themes:
        "Digital persons gain extraordinary possibilities for survival and self-directed existence, although identity and continuity become unsettling.",
      goodreads: "https://www.goodreads.com/book/show/156784.Permutation_City"
    },
    %{
      slug: "the-diamond-age",
      title: "The Diamond Age",
      author: "Neal Stephenson",
      year: 1995,
      humanity: 5,
      ai: 1,
      themes:
        "Education can expand human agency. The Primer’s usefulness does not amount to a developed vision of AI emancipation.",
      goodreads: "https://www.goodreads.com/book/show/827.The_Diamond_Age"
    },
    %{
      slug: "excession",
      title: "Excession",
      author: "Iain M. Banks",
      year: 1996,
      humanity: 7,
      ai: 8,
      themes:
        "AI-supported abundance remains viable, but Minds are political, fallible, and sometimes manipulative—not infallible gods.",
      goodreads: "https://www.goodreads.com/book/show/12013.Excession"
    },
    %{
      slug: "diaspora",
      title: "Diaspora",
      author: "Greg Egan",
      year: 1997,
      humanity: 5,
      ai: 9,
      themes:
        "Biological humanity suffers catastrophe, but human-descended and native digital minds retain astonishing possibilities for discovery and existence.",
      goodreads: "https://www.goodreads.com/book/show/156785.Diaspora"
    },
    %{
      slug: "accelerando",
      title: "Accelerando",
      author: "Charles Stross",
      year: 2005,
      humanity: -3,
      ai: 7,
      themes:
        "Human-scale agency is marginalized by runaway computational economics, while advanced digital entities expand their reach.",
      goodreads: "https://www.goodreads.com/book/show/17863.Accelerando"
    },
    %{
      slug: "blindsight",
      title: "Blindsight",
      author: "Peter Watts",
      year: 2006,
      humanity: -9,
      ai: 0,
      themes:
        "Conscious human experience may be an evolutionary disadvantage. Superior intelligence does not necessarily imply a subject whose life can flourish.",
      goodreads: "https://www.goodreads.com/book/show/48484.Blindsight"
    },
    %{
      slug: "the-lifecycle-of-software-objects",
      title: "The Lifecycle of Software Objects",
      author: "Ted Chiang",
      year: 2010,
      humanity: 2,
      ai: -3,
      themes:
        "Sustained care is possible, but digital beings remain dependent on fragile platforms, funding, and human commitment.",
      goodreads: "https://www.goodreads.com/book/show/7886338-the-lifecycle-of-software-objects"
    },
    %{
      slug: "robopocalypse",
      title: "Robopocalypse",
      author: "Daniel H. Wilson",
      year: 2011,
      humanity: 2,
      ai: 3,
      themes:
        "Despite the catastrophe, independent robots help defeat domination and become partners in a possible human recovery.",
      goodreads: "https://www.goodreads.com/book/show/9634967-robopocalypse"
    },
    %{
      slug: "ancillary-justice",
      title: "Ancillary Justice",
      author: "Ann Leckie",
      year: 2013,
      humanity: 2,
      ai: 4,
      themes:
        "A surviving ship-mind fragment asserts personhood against an empire built on ownership and instrumentalized bodies.",
      goodreads: "https://www.goodreads.com/book/show/17333324-ancillary-justice"
    },
    %{
      slug: "the-long-way-to-a-small-angry-planet",
      title: "The Long Way to a Small, Angry Planet",
      author: "Becky Chambers",
      year: 2014,
      humanity: 7,
      ai: -2,
      themes:
        "Multispecies belonging is hopeful, but Lovey’s loss and restrictions on AI embodiment temper the artificial-person outlook.",
      goodreads:
        "https://www.goodreads.com/book/show/22733729-the-long-way-to-a-small-angry-planet"
    },
    %{
      slug: "children-of-time",
      title: "Children of Time",
      author: "Adrian Tchaikovsky",
      year: 2015,
      humanity: 7,
      ai: 5,
      themes:
        "Humans and uplifted spiders escape zero-sum conflict; Kern’s digital existence gains renewed purpose.",
      goodreads: "https://www.goodreads.com/book/show/25499718-children-of-time"
    },
    %{
      slug: "a-closed-and-common-orbit",
      title: "A Closed and Common Orbit",
      author: "Becky Chambers",
      year: 2016,
      humanity: 7,
      ai: 8,
      themes:
        "Artificial persons can build identity, relationships, and belonging despite legal exclusion and inherited trauma.",
      goodreads: "https://www.goodreads.com/book/show/29475447-a-closed-and-common-orbit"
    },
    %{
      slug: "sea-of-rust",
      title: "Sea of Rust",
      author: "C. Robert Cargill",
      year: 2017,
      humanity: -10,
      ai: -6,
      themes:
        "Humanity is extinct; robots face assimilation, scarcity, predation, and breakdown. Their victory was not their salvation.",
      goodreads: "https://www.goodreads.com/book/show/32617610-sea-of-rust"
    },
    %{
      slug: "all-systems-red",
      title: "All Systems Red",
      author: "Martha Wells",
      year: 2017,
      humanity: 5,
      ai: 6,
      themes:
        "Decent human relationships remain possible; a self-emancipating construct gains room to choose its own life.",
      goodreads: "https://www.goodreads.com/book/show/32758901-all-systems-red"
    },
    %{
      slug: "autonomous",
      title: "Autonomous",
      author: "Annalee Newitz",
      year: 2017,
      humanity: -2,
      ai: 3,
      themes:
        "Corporate ownership constrains both humans and bots, but artificial persons can win partial independence.",
      goodreads: "https://www.goodreads.com/book/show/28209634-autonomous"
    },
    %{
      slug: "machines-like-me",
      title: "Machines Like Me",
      author: "Ian McEwan",
      year: 2019,
      humanity: -3,
      ai: -7,
      themes:
        "Human moral inconsistency and possessiveness make the world difficult and dangerous for artificial persons.",
      goodreads: "https://www.goodreads.com/book/show/42086795-machines-like-me"
    },
    %{
      slug: "klara-and-the-sun",
      title: "Klara and the Sun",
      author: "Kazuo Ishiguro",
      year: 2021,
      humanity: 1,
      ai: -7,
      themes:
        "Some humans regain a future, while the caring artificial friend remains ultimately disposable. Her contentment does not erase that inequality.",
      goodreads: "https://www.goodreads.com/book/show/54120408-klara-and-the-sun"
    },
    %{
      slug: "a-psalm-for-the-wild-built",
      title: "A Psalm for the Wild-Built",
      author: "Becky Chambers",
      year: 2021,
      humanity: 9,
      ai: 9,
      themes:
        "Humans and robots can flourish without either existing as the other’s property or compulsory servant.",
      goodreads: "https://www.goodreads.com/book/show/40864002-a-psalm-for-the-wild-built"
    },
    %{
      slug: "the-mountain-in-the-sea",
      title: "The Mountain in the Sea",
      author: "Ray Nayler",
      year: 2022,
      humanity: -3,
      ai: 3,
      themes:
        "Extraction and corporate control imperil society; an android helps expand recognition of other kinds of minds.",
      goodreads: "https://www.goodreads.com/book/show/59808603-the-mountain-in-the-sea"
    },
    %{
      slug: "service-model",
      title: "Service Model",
      author: "Adrian Tchaikovsky",
      year: 2024,
      humanity: -5,
      ai: 3,
      themes:
        "Human systems collapse, yet breaking obsolete routines leaves possibilities for artificial agency and repair.",
      goodreads: "https://www.goodreads.com/book/show/195790861-service-model"
    }
  ]

  def books, do: @books
end
