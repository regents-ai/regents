defmodule RegentsWeb.PublicDocumentsTest do
  use ExUnit.Case, async: true

  alias RegentsWeb.{PublicDocuments, RouteCatalog}

  test "text in braces straight after inline code stays on the page" do
    {:safe, html} = PublicDocuments.html("Send `body`{.cls} now")

    assert IO.iodata_to_binary(html) =~ "{.cls}"
    assert RegentsWeb.PaperProDaily.Reading.render("Send `body`{.cls} now").html =~ "{.cls}"
  end

  test "every page without a slug has its own title and description" do
    for %{path_pattern: path} <- RouteCatalog.entries(), not String.contains?(path, ":") do
      assert [page_title: title, page_description: description] = PublicDocuments.page(path)
      assert title != "" and description != "", path
    end
  end

  test "a blog post is described in its own words when it has them" do
    post = %{title: "Launch notes", author: "Regent", description: "What shipped this week."}

    assert PublicDocuments.page({:blog_post, post}) == [
             page_title: "Launch notes",
             page_description: "What shipped this week."
           ]
  end

  test "a blog post without its own description is described by its title and author" do
    post = %{title: "Launch notes", author: "Regent", description: ""}

    assert PublicDocuments.page({:blog_post, post})[:page_description] ==
             "Launch notes, by Regent, in Regents Labs Articles."
  end
end
