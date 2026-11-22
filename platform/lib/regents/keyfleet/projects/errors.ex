defmodule Regents.Keyfleet.Projects.Errors.UnknownProjectError do
  @moduledoc "Raised when a request names a project its fleet does not have."
  use Splode.Error, fields: [:fleet_id, :project], class: :invalid

  def message(%{fleet_id: fleet_id, project: project}),
    do: "#{fleet_id} has no project #{project}"
end

defmodule Regents.Keyfleet.Projects.Errors.NameTakenError do
  @moduledoc """
  Raised when a new project takes a name its fleet already uses, or once
  used: a deleted project's name is never used again.
  """
  use Splode.Error, fields: [:fleet_id, :name], class: :invalid

  def message(%{name: name}),
    do: "This fleet already has, or had, a project named #{name}. Choose another name."
end

defmodule Regents.Keyfleet.Projects.Errors.HoldError do
  @moduledoc """
  Raised when a Key may not start, archive, take over, delete, describe or
  show a project now, with the words that say why (`message`) and a short
  code for agents:

    * `active_held`: the Key is working on another project
    * `no_active`: the Key holds no active project to archive
    * `archive_full`: the Key already holds the most archived projects
    * `not_archived`: only an archived project is taken over or deleted
    * `not_creator`: only the Key that started a project deletes it
    * `not_holder`: only the Key that holds a project describes it or
      chooses who sees its work
    * `general_kept`: `general` is never deleted
    * `shared`: a project the whole fleet shares is never taken over or deleted
  """
  use Splode.Error, fields: [:code, :words, :project], class: :invalid

  def message(%{words: words}), do: words
end

defmodule Regents.Keyfleet.Projects.Errors.ClosedError do
  @moduledoc """
  Raised when work names a project that takes none: `project_archived` for
  an archived one, `project_unknown` for a name the fleet has no project
  by. `active` names the fleet's active projects, where new work goes.
  """
  use Splode.Error, fields: [:code, :project, :active], class: :invalid

  def message(%{code: :project_archived, project: project, active: active}),
    do: "#{project} is archived. " <> where(active)

  def message(%{code: :project_unknown, project: project, active: active}),
    do: "This fleet has no project named #{project}. " <> where(active)

  defp where([]), do: "No project is active; a Key starts one or takes one over."
  defp where(active), do: "New work goes into an active project: #{Enum.join(active, ", ")}."
end

defmodule Regents.Keyfleet.Projects.Errors.PublishError do
  @moduledoc """
  Raised when a Key may not make something public, or take it back, with the
  words that say why (`message`) and a short code for agents:

    * `project_archived`: posts go public only in an active project
    * `range`: the range runs backwards or spans too many posts
    * `room_unknown`: the fleet has no such room
    * `none_written`: the Key wrote no post in the range
    * `not_yours`: only the Key that made something public takes it back
    * `unknown`: the fleet has nothing public by that id
  """
  use Splode.Error, fields: [:code, :words], class: :invalid

  def message(%{words: words}), do: words
end
