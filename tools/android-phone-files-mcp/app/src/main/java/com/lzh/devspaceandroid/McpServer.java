package com.lzh.devspaceandroid;

import android.content.Context;

import fi.iki.elonen.NanoHTTPD;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

final class McpServer extends NanoHTTPD {
    static final int PORT = 7676;
    private static final int MAX_REQUEST_BODY_BYTES = 20 * 1024 * 1024;
    private final Context context;
    private final TokenStore tokenStore;
    private final FileTools fileTools;
    private final Map<String, PendingCode> pendingCodes = new HashMap<>();
    private final Map<String, DownloadLink> downloadLinks = new HashMap<>();

    McpServer(Context context) {
        super("0.0.0.0", PORT);
        Context appContext = context.getApplicationContext();
        this.context = appContext;
        tokenStore = new TokenStore(appContext);
        fileTools = new FileTools(appContext);
    }

    @Override
    public Response serve(IHTTPSession session) {
        try {
            if (Method.OPTIONS.equals(session.getMethod())) {
                return withCors(newFixedLengthResponse(Response.Status.NO_CONTENT, "text/plain", ""));
            }
            String uri = normalizeUri(session.getUri());
            if ("/healthz".equals(uri)) {
                return json(new JSONObject().put("ok", true).put("name", "devspace-android"));
            }
            if ("/relay_status".equals(uri)) {
                if (isForwardedRequest(session) && !isAuthorized(session)) {
                    Response response = json(Response.Status.UNAUTHORIZED, new JSONObject().put("error", "Unauthorized"));
                    response.addHeader("WWW-Authenticate", "Bearer");
                    return response;
                }
                RelayClient relayClient = RelayClient.get(context);
                return json(new JSONObject()
                    .put("relayBaseUrl", RelayConfig.getRelayBaseUrl(context))
                    .put("publicMcpUrl", RelayConfig.publicMcpUrl(context))
                    .put("mcpRunning", PhoneMcpService.isRunning())
                    .put("powerLocksHeld", PhoneMcpService.arePowerLocksHeld())
                    .put("watchdogStatus", PhoneMcpService.watchdogStatus())
                    .put("watchdogRestartCount", PhoneMcpService.watchdogRestartCount())
                    .put("lastWatchdogOkAt", PhoneMcpService.lastWatchdogOkAt())
                    .put("running", relayClient.isRunning())
                    .put("status", relayClient.statusLine())
                    .put("lastMessage", relayClient.lastMessage()));
            }
            if (isProtectedResourceMetadata(uri)) {
                return json(protectedResourceMetadata(baseUrl(session)));
            }
            if (isAuthorizationMetadata(uri)) {
                return json(authorizationMetadata(baseUrl(session)));
            }
            if ("/register".equals(uri)) {
                return handleRegister(session);
            }
            if ("/authorize".equals(uri)) {
                return handleAuthorize(session);
            }
            if ("/token".equals(uri)) {
                return handleToken(session);
            }
            if (uri.startsWith("/download/")) {
                return handleDownload(session, uri);
            }
            if ("/mcp".equals(uri)) {
                return handleMcp(session);
            }
            return text(Response.Status.NOT_FOUND, "Not found");
        } catch (Exception error) {
            return text(Response.Status.INTERNAL_ERROR, error.getMessage() == null ? error.toString() : error.getMessage());
        }
    }

    private Response handleRegister(IHTTPSession session) throws IOException, ResponseException, JSONException {
        String body = body(session);
        JSONArray redirectUris = new JSONArray();
        if (!body.isEmpty()) {
            JSONObject request = new JSONObject(body);
            redirectUris = request.optJSONArray("redirect_uris");
            if (redirectUris == null) {
                redirectUris = new JSONArray();
            }
        }
        JSONObject response = new JSONObject();
        response.put("client_id", "android-" + UUID.randomUUID());
        response.put("client_id_issued_at", System.currentTimeMillis() / 1000L);
        response.put("redirect_uris", redirectUris);
        response.put("grant_types", new JSONArray(List.of("authorization_code", "refresh_token")));
        response.put("response_types", new JSONArray(List.of("code")));
        response.put("token_endpoint_auth_method", "none");
        return json(response);
    }

    private Response handleAuthorize(IHTTPSession session) throws IOException, ResponseException {
        session.parseBody(new HashMap<>());
        Map<String, List<String>> params = session.getParameters();
        if (Method.POST.equals(session.getMethod())) {
            String ownerToken = first(params, "owner_token");
            if (!tokenStore.isOwnerToken(ownerToken)) {
                return html(Response.Status.UNAUTHORIZED, approvalPage(session, params, "Wrong owner token."));
            }
            String redirectUri = first(params, "redirect_uri");
            if (redirectUri == null || redirectUri.isEmpty()) {
                return text(Response.Status.BAD_REQUEST, "redirect_uri is required");
            }
            String code = randomToken();
            pendingCodes.put(code, new PendingCode(first(params, "client_id"), redirectUri));
            String state = first(params, "state");
            String location = redirectUri + (redirectUri.contains("?") ? "&" : "?") + "code=" + url(code)
                + (state == null ? "" : "&state=" + url(state));
            Response response = newFixedLengthResponse(Response.Status.REDIRECT, "text/plain", "Approved");
            response.addHeader("Location", location);
            return withCors(response);
        }
        return html(Response.Status.OK, approvalPage(session, params, null));
    }

    private Response handleToken(IHTTPSession session) throws IOException, ResponseException, JSONException {
        session.parseBody(new HashMap<>());
        Map<String, List<String>> params = session.getParameters();
        String grantType = first(params, "grant_type");
        if ("refresh_token".equals(grantType)) {
            String refreshToken = first(params, "refresh_token");
            if (!tokenStore.isRefreshToken(refreshToken)) {
                return json(Response.Status.BAD_REQUEST, new JSONObject().put("error", "invalid_grant"));
            }
            return json(tokenResponse(refreshToken));
        }
        String code = first(params, "code");
        if (grantType != null && !grantType.isEmpty() && !"authorization_code".equals(grantType)) {
            return json(Response.Status.BAD_REQUEST, new JSONObject().put("error", "unsupported_grant_type"));
        }
        if (code == null || code.isEmpty()) {
            return json(Response.Status.BAD_REQUEST, new JSONObject().put("error", "invalid_request"));
        }
        PendingCode pending = pendingCodes.remove(code);
        if (pending == null) {
            return json(Response.Status.BAD_REQUEST, new JSONObject().put("error", "invalid_grant"));
        }
        String refreshToken = randomToken();
        tokenStore.addRefreshToken(refreshToken);
        return json(tokenResponse(refreshToken));
    }

    private JSONObject tokenResponse(String refreshToken) throws JSONException {
        String accessToken = randomToken();
        tokenStore.addAccessToken(accessToken);
        JSONObject response = new JSONObject();
        response.put("access_token", accessToken);
        response.put("refresh_token", refreshToken);
        response.put("token_type", "Bearer");
        response.put("expires_in", 3600);
        response.put("scope", "phone.files");
        return response;
    }

    private Response handleMcp(IHTTPSession session) throws IOException, ResponseException, JSONException {
        if (!isAuthorized(session)) {
            Response response = json(Response.Status.UNAUTHORIZED, new JSONObject().put("error", "Unauthorized"));
            response.addHeader("WWW-Authenticate", "Bearer");
            return response;
        }
        String body = body(session);
        if (body.isEmpty()) {
            return text(Response.Status.BAD_REQUEST, "Missing JSON-RPC body");
        }
        JSONObject request = new JSONObject(body);
        if (!request.has("id")) {
            return withCors(newFixedLengthResponse(Response.Status.ACCEPTED, "text/plain", ""));
        }
        Object id = request.get("id");
        String method = request.optString("method", "");
        JSONObject result;
        switch (method) {
            case "initialize":
                result = initializeResult();
                break;
            case "tools/list":
                result = new JSONObject().put("tools", tools());
                break;
            case "tools/call":
                result = callTool(request.optJSONObject("params"), session);
                break;
            case "ping":
                result = new JSONObject();
                break;
            default:
                return json(jsonRpcError(id, -32601, "Unknown method: " + method));
        }
        Response response = json(new JSONObject().put("jsonrpc", "2.0").put("id", id).put("result", result));
        response.addHeader("Mcp-Session-Id", "phone");
        return response;
    }

    private JSONObject initializeResult() throws JSONException {
        return new JSONObject()
            .put("protocolVersion", "2025-06-18")
            .put("capabilities", new JSONObject().put("tools", new JSONObject().put("listChanged", false)))
            .put("serverInfo", new JSONObject().put("name", "devspace-android").put("version", "0.6.0"))
            .put("instructions", "This Android MCP server exposes phone files under the allowed root. Call open_workspace first, then use read_file, write_file, read_file_base64, write_file_base64, read_file_chunk_base64, write_file_chunk_base64, hash_file, list_directory, find_files, grep_files, stat_path, make_directory, delete_path, move_path, copy_path, zip_paths, unzip_file, and scan_media. Shell execution is intentionally disabled in this Android build.");
    }

    private JSONArray tools() throws JSONException {
        JSONArray tools = new JSONArray();
        tools.put(tool("open_workspace", "Open the phone file workspace.", new JSONObject()
            .put("type", "object")
            .put("properties", new JSONObject().put("path", stringSchema("Path under the allowed Android root. Defaults to .")))));
        tools.put(tool("list_roots", "List phone file roots and common storage locations exposed to GPT.", new JSONObject()
            .put("type", "object")
            .put("properties", new JSONObject())));
        tools.put(tool("read_file", "Read a UTF-8 text file from the phone.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path")))
            .put("properties", new JSONObject().put("path", stringSchema("File path under the allowed Android root.")))));
        tools.put(tool("read_file_auto", "Read a text file with automatic charset detection, including common Chinese encodings such as GB18030 and GBK.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path")))
            .put("properties", new JSONObject().put("path", stringSchema("File path under the allowed Android root.")))));
        tools.put(tool("read_lines", "Read a bounded line range from a text file with automatic charset detection.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path")))
            .put("properties", new JSONObject()
                .put("path", stringSchema("File path under the allowed Android root."))
                .put("start_line", integerSchema("1-based first line to read. Defaults to 1."))
                .put("line_count", integerSchema("Number of lines to read. Defaults to 200, maximum is 1000.")))));
        tools.put(tool("edit_file", "Edit a text file by replacing literal search text. The original file is backed up by default.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path", "search")))
            .put("properties", new JSONObject()
                .put("path", stringSchema("File path under the allowed Android root."))
                .put("search", stringSchema("Literal text to replace."))
                .put("replacement", stringSchema("Replacement text. Defaults to empty text."))
                .put("replace_all", booleanSchema("Replace all occurrences. Defaults to false."))
                .put("backup", booleanSchema("Create a timestamped backup before writing. Defaults to true.")))));
        tools.put(tool("file_preview", "Preview file metadata and the first bytes of a text-like file with charset detection.", new JSONObject()
            .put("type", "object")
            .put("properties", new JSONObject().put("path", stringSchema("Path under the allowed Android root. Defaults to .")))));
        tools.put(tool("create_download_link", "Create a short-lived public HTTPS download link for one phone file.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path")))
            .put("properties", new JSONObject()
                .put("path", stringSchema("File path under the allowed Android root."))
                .put("ttl_seconds", integerSchema("Link lifetime in seconds. Defaults to 600, maximum is 3600.")))));
        tools.put(tool("revoke_download_link", "Revoke a download link created by create_download_link.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("token")))
            .put("properties", new JSONObject().put("token", stringSchema("Download token returned by create_download_link.")))));
        tools.put(tool("write_file", "Write a UTF-8 text file on the phone.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path", "content")))
            .put("properties", new JSONObject()
                .put("path", stringSchema("File path under the allowed Android root."))
                .put("content", stringSchema("Text content to write.")))));
        tools.put(tool("read_file_base64", "Read a phone file as base64 for binary-safe transfer.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path")))
            .put("properties", new JSONObject().put("path", stringSchema("File path under the allowed Android root.")))));
        tools.put(tool("write_file_base64", "Write a phone file from base64 content for binary-safe transfer.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path", "content_base64")))
            .put("properties", new JSONObject()
                .put("path", stringSchema("File path under the allowed Android root."))
                .put("content_base64", stringSchema("Base64-encoded file bytes.")))));
        tools.put(tool("read_file_chunk_base64", "Read a chunk of a phone file as base64 for large binary files.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path", "offset", "length")))
            .put("properties", new JSONObject()
                .put("path", stringSchema("File path under the allowed Android root."))
                .put("offset", integerSchema("Zero-based byte offset."))
                .put("length", integerSchema("Bytes to read. Maximum chunk size is 4194304 bytes.")))));
        tools.put(tool("write_file_chunk_base64", "Write a base64 chunk into a phone file for large binary-safe transfer.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path", "offset", "content_base64")))
            .put("properties", new JSONObject()
                .put("path", stringSchema("File path under the allowed Android root."))
                .put("offset", integerSchema("Zero-based byte offset. Use 0 for the first chunk."))
                .put("content_base64", stringSchema("Base64-encoded chunk bytes. Maximum decoded chunk size is 4194304 bytes."))
                .put("truncate_before_write", booleanSchema("If true, truncate the file to offset before writing this chunk."))
                .put("truncate_after_write", booleanSchema("If true, truncate the file after the written chunk.")))));
        tools.put(tool("hash_file", "Compute a streaming SHA-256 hash for a phone file without transferring its contents.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path")))
            .put("properties", new JSONObject()
                .put("path", stringSchema("File path under the allowed Android root."))
                .put("algorithm", stringSchema("Hash algorithm. Supported: SHA-256. Defaults to SHA-256.")))));
        tools.put(tool("list_directory", "List a phone directory.", new JSONObject()
            .put("type", "object")
            .put("properties", new JSONObject().put("path", stringSchema("Directory path. Defaults to .")))));
        tools.put(tool("grep_files", "Search UTF-8 text files by substring.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("pattern")))
            .put("properties", new JSONObject()
                .put("pattern", stringSchema("Text to search for."))
                .put("path", stringSchema("Directory or file path. Defaults to .")))));
        tools.put(tool("find_files", "Find phone files or directories by name or relative path substring.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("query")))
            .put("properties", new JSONObject()
                .put("query", stringSchema("Case-insensitive filename or path substring to search for."))
                .put("path", stringSchema("Directory path to search from. Defaults to ."))
                .put("limit", integerSchema("Maximum result count. Defaults to 100, maximum is 500.")))));
        tools.put(tool("scan_media", "Ask Android's media scanner to index a file or a recursive directory under the allowed root.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path")))
            .put("properties", new JSONObject()
                .put("path", stringSchema("File or directory path under the allowed Android root."))
                .put("recursive", booleanSchema("Required when path is a directory. Queues up to 1000 files.")))));
        tools.put(tool("stat_path", "Get phone file or directory metadata.", new JSONObject()
            .put("type", "object")
            .put("properties", new JSONObject().put("path", stringSchema("Path under the allowed Android root. Defaults to .")))));
        tools.put(tool("make_directory", "Create a phone directory, including parents.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path")))
            .put("properties", new JSONObject().put("path", stringSchema("Directory path under the allowed Android root.")))));
        tools.put(tool("delete_path", "Delete a phone file or directory under the allowed root.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("path")))
            .put("properties", new JSONObject()
                .put("path", stringSchema("Path under the allowed Android root."))
                .put("recursive", booleanSchema("Required to delete non-empty directories.")))));
        tools.put(tool("move_path", "Move or rename a phone file or directory under the allowed root.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("from", "to")))
            .put("properties", new JSONObject()
                .put("from", stringSchema("Source path under the allowed Android root."))
                .put("to", stringSchema("Destination path under the allowed Android root."))
                .put("overwrite", booleanSchema("Overwrite an existing destination.")))));
        tools.put(tool("copy_path", "Copy a phone file or directory under the allowed root.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("from", "to")))
            .put("properties", new JSONObject()
                .put("from", stringSchema("Source path under the allowed Android root."))
                .put("to", stringSchema("Destination path under the allowed Android root."))
                .put("recursive", booleanSchema("Required to copy directories."))
                .put("overwrite", booleanSchema("Overwrite an existing destination.")))));
        tools.put(tool("zip_paths", "Create a zip archive from files or directories under the allowed root.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("paths", "output_path")))
            .put("properties", new JSONObject()
                .put("paths", new JSONObject().put("type", "array").put("items", stringSchema("Source path under the allowed Android root.")))
                .put("output_path", stringSchema("Output zip path under the allowed Android root."))
                .put("overwrite", booleanSchema("Overwrite an existing output zip.")))));
        tools.put(tool("unzip_file", "Extract a zip archive into a directory under the allowed root.", new JSONObject()
            .put("type", "object")
            .put("required", new JSONArray(List.of("zip_path", "destination_path")))
            .put("properties", new JSONObject()
                .put("zip_path", stringSchema("Zip file path under the allowed Android root."))
                .put("destination_path", stringSchema("Destination directory under the allowed Android root."))
                .put("overwrite", booleanSchema("Overwrite existing extracted files.")))));
        tools.put(tool("run_shell", "Return a disabled-shell notice for compatibility.", new JSONObject()
            .put("type", "object")
            .put("properties", new JSONObject().put("command", stringSchema("Command text.")))));
        return tools;
    }

    private JSONObject callTool(JSONObject params, IHTTPSession session) throws JSONException {
        if (params == null) {
            return toolText("Missing params.");
        }
        String name = params.optString("name", "");
        JSONObject args = params.optJSONObject("arguments");
        if (args == null) {
            args = new JSONObject();
        }
        try {
            switch (name) {
                case "open_workspace":
                    JSONObject workspace = fileTools.openWorkspace(args.optString("path", "."));
                    return toolText("Opened phone workspace phone\nRoot: " + workspace.optString("root")).put("structuredContent", workspace);
                case "list_roots":
                    return toolText(fileTools.knownRoots());
                case "read_file":
                    return toolText(fileTools.readFile(args.optString("path")));
                case "read_file_auto":
                    return toolText(fileTools.readFileAuto(args.optString("path")));
                case "read_lines":
                    return toolText(fileTools.readLines(args.optString("path"), args.optInt("start_line", 1), args.optInt("line_count", 200)));
                case "edit_file":
                    return toolText(fileTools.editFile(args.optString("path"), args.optString("search"), args.optString("replacement", ""), args.optBoolean("replace_all", false), args.optBoolean("backup", true)));
                case "file_preview":
                    return toolText(fileTools.filePreview(args.optString("path", ".")));
                case "create_download_link":
                    return createDownloadLink(args.optString("path"), args.optInt("ttl_seconds", 600), baseUrl(session));
                case "revoke_download_link":
                    return revokeDownloadLink(args.optString("token"));
                case "write_file":
                    return toolText(fileTools.writeFile(args.optString("path"), args.optString("content", "")));
                case "read_file_base64":
                    return toolText(fileTools.readFileBase64(args.optString("path")));
                case "write_file_base64":
                    return toolText(fileTools.writeFileBase64(args.optString("path"), args.optString("content_base64", "")));
                case "read_file_chunk_base64":
                    return toolText(fileTools.readFileChunkBase64(args.optString("path"), args.optLong("offset", 0), args.optInt("length", 1048576)));
                case "write_file_chunk_base64":
                    return toolText(fileTools.writeFileChunkBase64(args.optString("path"), args.optLong("offset", 0), args.optString("content_base64", ""), args.optBoolean("truncate_before_write", false), args.optBoolean("truncate_after_write", false)));
                case "hash_file":
                    return toolText(fileTools.hashFile(args.optString("path"), args.optString("algorithm", "SHA-256")));
                case "list_directory":
                    return toolText(fileTools.listDirectory(args.optString("path", ".")));
                case "grep_files":
                    return toolText(fileTools.grepFiles(args.optString("pattern"), args.optString("path", ".")));
                case "find_files":
                    return toolText(fileTools.findFiles(args.optString("query"), args.optString("path", "."), args.optInt("limit", 100)));
                case "scan_media":
                    return toolText(fileTools.scanMedia(args.optString("path"), args.optBoolean("recursive", false)));
                case "stat_path":
                    return toolText(fileTools.statPath(args.optString("path", ".")));
                case "make_directory":
                    return toolText(fileTools.makeDirectory(args.optString("path")));
                case "delete_path":
                    return toolText(fileTools.deletePath(args.optString("path"), args.optBoolean("recursive", false)));
                case "move_path":
                    return toolText(fileTools.movePath(args.optString("from"), args.optString("to"), args.optBoolean("overwrite", false)));
                case "copy_path":
                    return toolText(fileTools.copyPath(args.optString("from"), args.optString("to"), args.optBoolean("recursive", false), args.optBoolean("overwrite", false)));
                case "zip_paths":
                    return toolText(fileTools.zipPaths(args.optJSONArray("paths"), args.optString("output_path"), args.optBoolean("overwrite", false)));
                case "unzip_file":
                    return toolText(fileTools.unzipFile(args.optString("zip_path"), args.optString("destination_path"), args.optBoolean("overwrite", false)));
                case "run_shell":
                    return toolText("run_shell is disabled in this Android build. Use file tools for phone file control.");
                default:
                    return toolText("Unknown tool: " + name);
            }
        } catch (Exception error) {
            return toolText("Error: " + (error.getMessage() == null ? error.toString() : error.getMessage())).put("isError", true);
        }
    }

    private JSONObject createDownloadLink(String path, int ttlSeconds, String baseUrl) throws IOException, JSONException {
        File file = fileTools.resolvePath(path);
        if (!file.isFile()) {
            throw new IOException("Not a file: " + file.getAbsolutePath());
        }
        int ttl = ttlSeconds <= 0 ? 600 : Math.min(ttlSeconds, 3600);
        cleanupExpiredDownloadLinks();
        String token = randomToken();
        long expiresAt = System.currentTimeMillis() + ttl * 1000L;
        downloadLinks.put(token, new DownloadLink(file.getCanonicalFile(), expiresAt));
        String url = baseUrl + "/download/" + url(token);
        JSONObject output = new JSONObject()
            .put("url", url)
            .put("token", token)
            .put("path", file.getAbsolutePath())
            .put("bytes", file.length())
            .put("expiresAt", expiresAt)
            .put("ttlSeconds", ttl);
        return toolText("Download link: " + url).put("structuredContent", output);
    }

    private JSONObject revokeDownloadLink(String token) throws JSONException {
        boolean removed = false;
        if (token != null && !token.isEmpty()) {
            removed = downloadLinks.remove(token) != null;
        }
        JSONObject output = new JSONObject()
            .put("revoked", removed);
        return toolText(removed ? "Download link revoked." : "Download link was not found.").put("structuredContent", output);
    }

    private Response handleDownload(IHTTPSession session, String uri) throws IOException {
        String token = uri.substring("/download/".length());
        DownloadLink link = token == null || token.isEmpty() ? null : downloadLinks.get(token);
        if (link == null) {
            return text(Response.Status.NOT_FOUND, "Download link not found or expired.");
        }
        if (System.currentTimeMillis() > link.expiresAt) {
            downloadLinks.remove(token);
            return text(Response.Status.GONE, "Download link expired.");
        }
        File file = link.file;
        if (!file.isFile()) {
            downloadLinks.remove(token);
            return text(Response.Status.NOT_FOUND, "File no longer exists.");
        }
        Response response = newChunkedResponse(Response.Status.OK, contentType(file), new FileInputStream(file));
        response.addHeader("Content-Length", String.valueOf(file.length()));
        response.addHeader("Content-Disposition", contentDisposition(file.getName()));
        response.addHeader("Cache-Control", "private, max-age=0, no-store");
        return withCors(response);
    }

    private void cleanupExpiredDownloadLinks() {
        long now = System.currentTimeMillis();
        downloadLinks.entrySet().removeIf(entry -> entry.getValue().expiresAt < now);
    }

    private boolean isAuthorized(IHTTPSession session) {
        String authorization = session.getHeaders().get("authorization");
        if (authorization == null) {
            return false;
        }
        String prefix = "bearer ";
        if (!authorization.toLowerCase(Locale.ROOT).startsWith(prefix)) {
            return false;
        }
        String token = authorization.substring(prefix.length()).trim();
        return tokenStore.isOwnerToken(token) || tokenStore.isAccessToken(token);
    }

    private boolean isForwardedRequest(IHTTPSession session) {
        Map<String, String> headers = session.getHeaders();
        return hasHeader(headers, "x-forwarded-host")
            || hasHeader(headers, "x-forwarded-proto")
            || hasHeader(headers, "x-forwarded-prefix");
    }

    private boolean hasHeader(Map<String, String> headers, String key) {
        String value = headers.get(key);
        return value != null && !value.isEmpty();
    }

    private JSONObject protectedResourceMetadata(String baseUrl) throws JSONException {
        return new JSONObject()
            .put("resource", baseUrl + "/mcp")
            .put("authorization_servers", new JSONArray(List.of(baseUrl)))
            .put("scopes_supported", new JSONArray(List.of("phone.files")))
            .put("resource_name", "DevSpace Android");
    }

    private JSONObject authorizationMetadata(String baseUrl) throws JSONException {
        return new JSONObject()
            .put("issuer", baseUrl)
            .put("authorization_endpoint", baseUrl + "/authorize")
            .put("token_endpoint", baseUrl + "/token")
            .put("registration_endpoint", baseUrl + "/register")
            .put("response_types_supported", new JSONArray(List.of("code")))
            .put("grant_types_supported", new JSONArray(List.of("authorization_code", "refresh_token")))
            .put("code_challenge_methods_supported", new JSONArray(List.of("S256", "plain")))
            .put("token_endpoint_auth_methods_supported", new JSONArray(List.of("none")))
            .put("scopes_supported", new JSONArray(List.of("phone.files")));
    }

    private JSONObject tool(String name, String description, JSONObject inputSchema) throws JSONException {
        return new JSONObject()
            .put("name", name)
            .put("title", name)
            .put("description", description)
            .put("inputSchema", inputSchema);
    }

    private JSONObject stringSchema(String description) throws JSONException {
        return new JSONObject().put("type", "string").put("description", description);
    }

    private JSONObject booleanSchema(String description) throws JSONException {
        return new JSONObject().put("type", "boolean").put("description", description);
    }

    private JSONObject integerSchema(String description) throws JSONException {
        return new JSONObject().put("type", "integer").put("description", description);
    }

    private JSONObject toolText(String text) throws JSONException {
        return new JSONObject().put("content", new JSONArray().put(new JSONObject().put("type", "text").put("text", text)));
    }

    private JSONObject jsonRpcError(Object id, int code, String message) throws JSONException {
        return new JSONObject()
            .put("jsonrpc", "2.0")
            .put("id", id)
            .put("error", new JSONObject().put("code", code).put("message", message));
    }

    private Response html(Response.Status status, String html) {
        return withCors(newFixedLengthResponse(status, "text/html; charset=utf-8", html));
    }

    private Response text(Response.Status status, String text) {
        return withCors(newFixedLengthResponse(status, "text/plain; charset=utf-8", text == null ? "" : text));
    }

    private Response json(JSONObject json) {
        return json(Response.Status.OK, json);
    }

    private Response json(Response.Status status, JSONObject json) {
        return withCors(newFixedLengthResponse(status, "application/json; charset=utf-8", json.toString()));
    }

    private Response withCors(Response response) {
        response.addHeader("Access-Control-Allow-Origin", "*");
        response.addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        response.addHeader("Access-Control-Allow-Headers", "Authorization, Content-Type, Accept, MCP-Protocol-Version, Mcp-Session-Id");
        response.addHeader("Access-Control-Expose-Headers", "Mcp-Session-Id");
        return response;
    }

    private String body(IHTTPSession session) throws IOException, ResponseException {
        String contentLengthHeader = session.getHeaders().get("content-length");
        if (contentLengthHeader == null || contentLengthHeader.isEmpty()) {
            Map<String, String> files = new HashMap<>();
            session.parseBody(files);
            String parsedBody = files.get("postData");
            return parsedBody == null ? "" : parsedBody;
        }
        int contentLength;
        try {
            contentLength = Integer.parseInt(contentLengthHeader.trim());
        } catch (NumberFormatException error) {
            throw new IOException("Invalid content-length: " + contentLengthHeader, error);
        }
        if (contentLength < 0) {
            throw new IOException("Invalid negative content-length: " + contentLength);
        }
        if (contentLength > MAX_REQUEST_BODY_BYTES) {
            throw new IOException("Request body is too large: " + contentLength + " bytes.");
        }
        InputStream input = session.getInputStream();
        ByteArrayOutputStream output = new ByteArrayOutputStream(contentLength);
        byte[] buffer = new byte[8192];
        int remaining = contentLength;
        while (remaining > 0) {
            int read = input.read(buffer, 0, Math.min(buffer.length, remaining));
            if (read == -1) {
                break;
            }
            output.write(buffer, 0, read);
            remaining -= read;
        }
        return new String(output.toByteArray(), StandardCharsets.UTF_8);
    }

    private String approvalPage(IHTTPSession session, Map<String, List<String>> params, String error) {
        StringBuilder hidden = new StringBuilder();
        for (Map.Entry<String, List<String>> entry : params.entrySet()) {
            String value = entry.getValue().isEmpty() ? "" : entry.getValue().get(0);
            hidden.append("<input type=\"hidden\" name=\"").append(escape(entry.getKey())).append("\" value=\"").append(escape(value)).append("\">");
        }
        String action = escape(baseUrl(session) + "/authorize");
        return "<!doctype html><html><head><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            + "<title>Approve DevSpace Android</title>"
            + "<style>body{font-family:sans-serif;margin:24px;line-height:1.4}input,button{font-size:16px;padding:10px;width:100%;box-sizing:border-box}button{margin-top:12px;background:#2f6f73;color:white;border:0}</style>"
            + "</head><body><h1>Approve DevSpace Android</h1>"
            + "<p>Enter the owner token shown inside the Android app.</p>"
            + (error == null ? "" : "<p style=\"color:#b00020\">" + escape(error) + "</p>")
            + "<form method=\"post\" action=\"" + action + "\">" + hidden
            + "<input name=\"owner_token\" autocomplete=\"off\" placeholder=\"Owner token\">"
            + "<button type=\"submit\">Approve</button></form></body></html>";
    }

    private String normalizeUri(String uri) {
        if (uri == null || uri.isEmpty()) {
            return "/";
        }
        return uri.endsWith("/") && uri.length() > 1 ? uri.substring(0, uri.length() - 1) : uri;
    }

    private boolean isProtectedResourceMetadata(String uri) {
        return "/.well-known/oauth-protected-resource".equals(uri)
            || "/.well-known/oauth-protected-resource/mcp".equals(uri)
            || "/mcp/.well-known/oauth-protected-resource".equals(uri);
    }

    private boolean isAuthorizationMetadata(String uri) {
        return "/.well-known/oauth-authorization-server".equals(uri)
            || "/.well-known/oauth-authorization-server/mcp".equals(uri)
            || "/mcp/.well-known/oauth-authorization-server".equals(uri);
    }

    private String baseUrl(IHTTPSession session) {
        String host = session.getHeaders().get("x-forwarded-host");
        if (host == null || host.isEmpty()) {
            host = session.getHeaders().get("host");
        }
        if (host == null || host.isEmpty()) {
            host = "127.0.0.1:" + PORT;
        }
        String proto = session.getHeaders().get("x-forwarded-proto");
        if (proto == null || proto.isEmpty()) {
            proto = "http";
        }
        String prefix = session.getHeaders().get("x-forwarded-prefix");
        if (prefix == null || prefix.isEmpty() || !prefix.startsWith("/")) {
            prefix = "";
        }
        while (prefix.endsWith("/") && prefix.length() > 1) {
            prefix = prefix.substring(0, prefix.length() - 1);
        }
        return proto + "://" + host + prefix;
    }

    private String first(Map<String, List<String>> params, String key) {
        List<String> values = params.get(key);
        return values == null || values.isEmpty() ? null : values.get(0);
    }

    private String randomToken() {
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);
        return java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private String escape(String value) {
        if (value == null) {
            return "";
        }
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
    }

    private String url(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    private String contentDisposition(String filename) {
        String safe = filename == null || filename.isEmpty() ? "download" : filename.replace("\\", "_").replace("\"", "'");
        String encoded = URLEncoder.encode(safe, StandardCharsets.UTF_8).replace("+", "%20");
        return "attachment; filename=\"" + escape(safe) + "\"; filename*=UTF-8''" + encoded;
    }

    private String contentType(File file) {
        String name = file.getName().toLowerCase(Locale.ROOT);
        if (name.endsWith(".txt") || name.endsWith(".log") || name.endsWith(".md") || name.endsWith(".csv")) {
            return "text/plain; charset=utf-8";
        }
        if (name.endsWith(".json")) {
            return "application/json; charset=utf-8";
        }
        if (name.endsWith(".pdf")) {
            return "application/pdf";
        }
        if (name.endsWith(".zip")) {
            return "application/zip";
        }
        if (name.endsWith(".png")) {
            return "image/png";
        }
        if (name.endsWith(".jpg") || name.endsWith(".jpeg")) {
            return "image/jpeg";
        }
        return "application/octet-stream";
    }

    private static final class PendingCode {
        final String clientId;
        final String redirectUri;

        PendingCode(String clientId, String redirectUri) {
            this.clientId = clientId;
            this.redirectUri = redirectUri;
        }
    }

    private static final class DownloadLink {
        final File file;
        final long expiresAt;

        DownloadLink(File file, long expiresAt) {
            this.file = file;
            this.expiresAt = expiresAt;
        }
    }
}
