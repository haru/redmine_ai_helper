// Chat history sidebar and hamburger dropdown menu methods for AiHelper.
// Split out of ai_helper.js to keep that file under the max-lines ESLint
// limit (see ADR-027). A classic script can't split a single class body
// across files, so this file extends AiHelper's prototype after the class
// is declared instead — same behavior as if these were defined inline in
// the class body. Must load after ai_helper.js (which declares
// `window.AiHelper`).

Object.assign(AiHelper.prototype, {
  reload_chat() {
    const chatArea = document.getElementById("aihelper-chat-conversation");
    if (!chatArea) {return;}

    // Hide interactive options when chat reloads (they are re-rendered fresh)
    ai_helper.hideInteractiveOptions();

    const xhr = new XMLHttpRequest();
    xhr.open("GET", ai_helper_urls.reload, true);

    xhr.onload = function () {
      if (xhr.status === 200) {
        ai_helper.innerHTMLwithScripts(chatArea, xhr.responseText);
        chatArea.scrollTop = chatArea.scrollHeight;
      } else {
        console.error("Failed to reload chat conversation:", xhr.statusText);
      }
    };

    xhr.onerror = function () {
      console.error("Failed to reload chat conversation:", xhr.statusText);
    };

    xhr.send();
  },

  load_history() {
    const historyContainer = document.getElementById("aihelper-history");
    if (!historyContainer) {return;}

    const xhr = new XMLHttpRequest();
    xhr.open("GET", ai_helper_urls.history, true);

    xhr.onload = function () {
      if (xhr.status === 200) {
        ai_helper.innerHTMLwithScripts(historyContainer, xhr.responseText);
      } else {
        console.error("Failed to reload chat conversation:", xhr.statusText);
      }
    };

    xhr.onerror = function () {
      console.error("Failed to reload chat conversation:", xhr.statusText);
    };

    xhr.send();
  },

  clear_chat() {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", ai_helper_urls.clear, true);

    xhr.onload = function () {
      if (xhr.status === 200) {
        ai_helper.close_dropdown_menu();
        ai_helper.reload_chat();
      } else {
        console.error("Failed to reload chat conversation:", xhr.statusText);
      }
    };

    xhr.onerror = function () {
      console.error("Failed to reload chat conversation:", xhr.statusText);
    };

    xhr.send();
  },

  set_hamberger_menu() {
    // Click event for hamburger menu
    const hamburgerButtons = document.querySelectorAll(".aihelper-hamburger");
    hamburgerButtons.forEach(button => {
      button.addEventListener("click", function (event) {
        ai_helper.load_history();
        event.stopPropagation();
        this.classList.toggle("active");

        const dropdownMenu = document.querySelector(".aihelper-dropdown-menu");
        if (dropdownMenu) {
          if (dropdownMenu.style.display === "none" || !dropdownMenu.style.display) {
            dropdownMenu.style.display = "block";
            // Animation effect
            const height = dropdownMenu.scrollHeight;
            dropdownMenu.style.height = "0px";
            dropdownMenu.style.overflow = "hidden";
            dropdownMenu.style.transition = "height 300ms";
            setTimeout(() => {
              dropdownMenu.style.height = height + "px";
            }, 10);
            setTimeout(() => {
              dropdownMenu.style.height = "";
              dropdownMenu.style.overflow = "";
              dropdownMenu.style.transition = "";
            }, 310);
          } else {
            // Animation effect
            const height = dropdownMenu.scrollHeight;
            dropdownMenu.style.height = height + "px";
            dropdownMenu.style.overflow = "hidden";
            dropdownMenu.style.transition = "height 300ms";
            setTimeout(() => {
              dropdownMenu.style.height = "0px";
            }, 10);
            setTimeout(() => {
              dropdownMenu.style.display = "none";
              dropdownMenu.style.height = "";
              dropdownMenu.style.overflow = "";
              dropdownMenu.style.transition = "";
            }, 310);
          }
        }
      });
    });

    // Stop propagation of click events inside the dropdown menu
    const dropdownMenus = document.querySelectorAll(".aihelper-dropdown-menu");
    dropdownMenus.forEach(menu => {
      menu.addEventListener("click", function (event) {
        event.stopPropagation();
      });
    });

    // Close the dropdown menu when clicking anywhere on the document
    document.addEventListener("click", function () {
      ai_helper.close_dropdown_menu();
    });
  },

  close_dropdown_menu() {
    const hamburgerButtons = document.querySelectorAll(".aihelper-hamburger");
    hamburgerButtons.forEach(button => {
      button.classList.remove("active");
    });

    const dropdownMenus = document.querySelectorAll(".aihelper-dropdown-menu");
    dropdownMenus.forEach(menu => {
      // Alternative for animation effect
      const height = menu.scrollHeight;
      menu.style.height = height + "px";
      menu.style.overflow = "hidden";
      menu.style.transition = "height 300ms";
      setTimeout(() => {
        menu.style.height = "0px";
      }, 10);
      setTimeout(() => {
        menu.style.display = "none";
        menu.style.height = "";
        menu.style.overflow = "";
        menu.style.transition = "";
      }, 310);
    });
  },

  jump_to_history(event, url) {
    event.preventDefault();
    const chatArea = document.getElementById("aihelper-chat-conversation");
    if (!chatArea) {return;}

    const xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);

    xhr.onload = function () {
      if (xhr.status === 200) {
        ai_helper.close_dropdown_menu();
        ai_helper.fold_chat(false);
        ai_helper.innerHTMLwithScripts(chatArea, xhr.responseText);
        chatArea.scrollTop = 0;
      } else {
        console.error("Failed to reload chat conversation:", xhr.statusText);
      }
    };

    xhr.onerror = function () {
      console.error("Failed to reload chat conversation:", xhr.statusText);
    };

    xhr.send();
  },

  delete_history(event, url) {
    event.preventDefault();
    const xhr = new XMLHttpRequest();
    xhr.open("DELETE", url, true);

    // Add CSRF token to header if needed
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    if (csrfToken) {
      xhr.setRequestHeader('X-CSRF-Token', csrfToken);
    }

    xhr.onload = function () {
      if (xhr.status === 200) {
        ai_helper.load_history();
        try {
          const data = JSON.parse(xhr.responseText);
          if (data["reload"]) {
            ai_helper.reload_chat();
          }
        } catch (e) {
          console.error("Failed to parse response:", e);
        }
      } else {
        console.error("Failed to reload chat conversation:", xhr.statusText);
      }
    };

    xhr.onerror = function () {
      console.error("Failed to reload chat conversation:", xhr.statusText);
    };

    xhr.send();
  },
});
