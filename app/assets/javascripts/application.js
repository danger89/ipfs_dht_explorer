//= require jquery3
//= require popper
//= require bootstrap
//= require chartkick
//= require turbolinks

//= require_tree .

document.addEventListener("turbolinks:load", function() {
  $(".dropdown-item").click(function (e) {
    if ($(this).data()["alt"]) {
      if(e.ctrlKey || e.metaKey || e.shiftKey){
        e.preventDefault();
        Turbolinks.visit($(this).data().alt)
      }
      if(e.altKey){
        e.preventDefault();
        Turbolinks.visit($(this).data().add)
      }
    }
  });
})
