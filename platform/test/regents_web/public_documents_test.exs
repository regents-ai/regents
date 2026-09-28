defmodule RegentsWeb.PublicDocumentsTest do
  use ExUnit.Case, async: true

  alias RegentsWeb.PublicDocuments

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
             "Launch notes, by Regent, on the Regents Labs blog."
  end
end
