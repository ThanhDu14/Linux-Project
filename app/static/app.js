// Giao diện todo: gọi API /api/* (Nginx proxy về Flask). Không có script inline, không dùng innerHTML
// với dữ liệu người dùng (chỉ textContent) → không bị XSS qua tiêu đề todo.
"use strict";

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

let authMode = "login"; // login | register
let filter = "all"; // all | active | done
let todos = [];

async function api(method, path, body) {
  // X-Requested-With: Flask từ chối request ghi không có header này (chống CSRF)
  const opts = { method, headers: { "X-Requested-With": "XMLHttpRequest" }, credentials: "same-origin" };
  if (body !== undefined) {
    opts.headers["Content-Type"] = "application/json";
    opts.body = JSON.stringify(body);
  }
  const res = await fetch("/api" + path, opts);
  if (res.status === 401 && path !== "/login") {
    showAuth();
    throw new Error("Phiên đăng nhập đã hết, hãy đăng nhập lại");
  }
  if (res.status === 429) throw new Error("Thử quá nhiều lần, đợi 1 phút rồi thử lại");
  if (res.status === 204) return null;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `Lỗi ${res.status}`);
  return data;
}

function showError(id, err) {
  $(id).textContent = err ? err.message || String(err) : "";
}

function selectTab(buttons, attr, value) {
  buttons.forEach((b) => b.setAttribute("aria-selected", String(b.dataset[attr] === value)));
}

// ---------- Đăng nhập / đăng ký ----------
function setAuthMode(mode) {
  authMode = mode;
  const reg = mode === "register";
  selectTab($$(".tabs button"), "mode", mode);
  $("#confirm-row").hidden = !reg;
  $("#auth-hint").hidden = !reg;
  $("#auth-form").confirm.required = reg;
  $("#auth-form").password.autocomplete = reg ? "new-password" : "current-password";
  $("#auth-submit").textContent = reg ? "Tạo tài khoản" : "Đăng nhập";
  showError("#auth-error");
}

function showAuth() {
  $("#todo-view").hidden = true;
  $("#auth-view").hidden = false;
  $("#todo-list").replaceChildren();
  $("#auth-form").username.focus();
}

async function showTodos(username) {
  $("#whoami").textContent = username;
  $("#auth-view").hidden = true;
  $("#todo-view").hidden = false;
  showError("#todo-error");
  await loadTodos();
  $("#add-form").title.focus();
}

// ---------- Danh sách ----------
async function loadTodos() {
  todos = await api("GET", "/todos");
  render();
}

function render() {
  const done = todos.filter((t) => t.done).length;
  $("#counter").textContent = todos.length ? `Đã xong ${done}/${todos.length}` : "";
  const shown = todos.filter((t) => filter === "all" || (filter === "done") === t.done);
  $("#todo-list").replaceChildren(...shown.map(renderItem));
  const empty = $("#empty");
  empty.hidden = shown.length > 0;
  empty.textContent = todos.length === 0 ? "Chưa có việc nào — thêm việc đầu tiên ở trên." : "Không có việc nào trong mục này.";
}

// Thao tác xong thì tải lại danh sách; lỗi thì hiện ra
async function run(action) {
  showError("#todo-error");
  try {
    await action();
    await loadTodos();
  } catch (err) {
    showError("#todo-error", err);
  }
}

function button(text, cls, title, onClick) {
  const b = document.createElement("button");
  b.type = "button";
  b.textContent = text;
  b.className = cls;
  b.title = title;
  b.setAttribute("aria-label", title);
  b.addEventListener("click", onClick);
  return b;
}

function renderItem(todo) {
  const li = document.createElement("li");
  li.classList.toggle("done", todo.done);

  const check = document.createElement("input");
  check.type = "checkbox";
  check.checked = todo.done;
  check.setAttribute("aria-label", "Đánh dấu xong");
  check.addEventListener("change", () => run(() => api("PATCH", `/todos/${todo.id}`, { done: check.checked })));

  const title = document.createElement("span");
  title.className = "title";
  title.textContent = todo.title;
  title.addEventListener("dblclick", () => startEdit(title, todo));

  const actions = document.createElement("span");
  actions.className = "actions";
  actions.append(
    button("✎", "icon", "Sửa", () => startEdit(title, todo)),
    button("✕", "icon danger", "Xoá", () => {
      if (confirm(`Xoá "${todo.title}"?`)) run(() => api("DELETE", `/todos/${todo.id}`));
    }),
  );

  li.append(check, title, actions);
  return li;
}

function startEdit(titleEl, todo) {
  const input = document.createElement("input");
  input.className = "edit";
  input.value = todo.title;
  input.maxLength = 200;
  let finished = false;
  const finish = (save) => {
    if (finished) return;
    finished = true;
    const value = input.value.trim();
    if (save && value && value !== todo.title) {
      run(() => api("PATCH", `/todos/${todo.id}`, { title: value }));
    } else {
      input.replaceWith(titleEl);
    }
  };
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") finish(true);
    if (e.key === "Escape") finish(false);
  });
  input.addEventListener("blur", () => finish(true));
  titleEl.replaceWith(input);
  input.focus();
  input.select();
}

// ---------- Sự kiện ----------
$$(".tabs button").forEach((b) => b.addEventListener("click", () => setAuthMode(b.dataset.mode)));

$$(".filters button").forEach((b) =>
  b.addEventListener("click", () => {
    filter = b.dataset.filter;
    selectTab($$(".filters button"), "filter", filter);
    render();
  }),
);

$("#auth-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const form = e.target;
  showError("#auth-error");
  if (authMode === "register" && form.password.value !== form.confirm.value) {
    showError("#auth-error", new Error("Hai mật khẩu không khớp"));
    return;
  }
  const submit = $("#auth-submit");
  submit.disabled = true;
  try {
    const me = await api("POST", `/${authMode}`, { username: form.username.value.trim(), password: form.password.value });
    form.reset();
    setAuthMode("login");
    await showTodos(me.username);
  } catch (err) {
    showError("#auth-error", err);
  } finally {
    submit.disabled = false;
  }
});

$("#add-form").addEventListener("submit", (e) => {
  e.preventDefault();
  const input = e.target.title;
  const title = input.value.trim();
  if (!title) return;
  run(async () => {
    await api("POST", "/todos", { title });
    input.value = "";
  });
});

$("#logout").addEventListener("click", async () => {
  await api("POST", "/logout").catch(() => {});
  showAuth();
});

// Đã có phiên (cookie còn hạn) → vào thẳng danh sách
api("GET", "/me")
  .then((me) => showTodos(me.username))
  .catch(() => showAuth());
