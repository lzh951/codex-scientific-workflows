package com.lzh.devspaceandroid;

import android.content.Context;
import android.media.MediaScannerConnection;
import android.os.Build;
import android.os.Environment;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

final class FileTools {
    private static final long MAX_READ_BYTES = 2L * 1024L * 1024L;
    private static final long MAX_BINARY_BYTES = 10L * 1024L * 1024L;
    private static final int MAX_CHUNK_BYTES = 4 * 1024 * 1024;
    private static final int MAX_GREP_MATCHES = 200;
    private static final int MAX_FIND_RESULTS = 500;
    private static final int MAX_MEDIA_SCAN_FILES = 1000;
    private static final int MAX_ZIP_ENTRIES = 2000;
    private static final long MAX_ZIP_BYTES = 512L * 1024L * 1024L;
    private final Context context;

    FileTools(Context context) {
        this.context = context.getApplicationContext();
    }

    File allowedRoot() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()) {
            return Environment.getExternalStorageDirectory();
        }
        return context.getFilesDir();
    }

    String rootLabel() {
        return allowedRoot().getAbsolutePath();
    }

    String knownRoots() {
        File root = allowedRoot();
        StringBuilder out = new StringBuilder();
        out.append("Primary allowed root: ").append(root.getAbsolutePath()).append("\n");
        addKnownRoot(out, "Download", new File(root, "Download"));
        addKnownRoot(out, "Documents", new File(root, "Documents"));
        addKnownRoot(out, "DCIM", new File(root, "DCIM"));
        addKnownRoot(out, "Pictures", new File(root, "Pictures"));
        addKnownRoot(out, "Movies", new File(root, "Movies"));
        addKnownRoot(out, "Music", new File(root, "Music"));
        addKnownRoot(out, "Recordings", new File(root, "Recordings"));
        addKnownRoot(out, "Android", new File(root, "Android"));
        addKnownRoot(out, "App private files", context.getFilesDir());
        addKnownRoot(out, "App cache", context.getCacheDir());
        out.append("Note: Android may still restrict direct access to Android/data and Android/obb on recent versions.\n");
        return out.toString();
    }

    JSONObject openWorkspace(String requestedPath) throws JSONException, IOException {
        File root = resolvePath(requestedPath == null || requestedPath.isEmpty() ? "." : requestedPath);
        if (!root.exists()) {
            throw new IOException("Workspace path does not exist: " + pathForUser(root));
        }
        if (!root.isDirectory()) {
            throw new IOException("Workspace path is not a directory: " + pathForUser(root));
        }
        JSONObject output = new JSONObject();
        output.put("workspaceId", "phone");
        output.put("root", pathForUser(root));
        output.put("mode", "phone");
        output.put("agentsFiles", new JSONArray());
        output.put("availableAgentsFiles", new JSONArray());
        output.put("skills", new JSONArray());
        output.put("instruction", "Use workspaceId phone for later calls. Paths are resolved under the Android allowed root.");
        return output;
    }

    String readFile(String path) throws IOException {
        File file = resolvePath(path);
        if (!file.isFile()) {
            throw new IOException("Not a file: " + pathForUser(file));
        }
        long length = file.length();
        if (length > MAX_READ_BYTES) {
            throw new IOException("File is too large for one read: " + length + " bytes. Limit is " + MAX_READ_BYTES + " bytes.");
        }
        return new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8);
    }

    String writeFile(String path, String content) throws IOException {
        File file = resolvePath(path);
        File parent = file.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("Could not create parent directory: " + pathForUser(parent));
        }
        Files.write(file.toPath(), (content == null ? "" : content).getBytes(StandardCharsets.UTF_8));
        return "Wrote " + pathForUser(file) + " (" + file.length() + " bytes)";
    }

    String readFileBase64(String path) throws IOException {
        File file = resolvePath(path);
        if (!file.isFile()) {
            throw new IOException("Not a file: " + pathForUser(file));
        }
        long length = file.length();
        if (length > MAX_BINARY_BYTES) {
            throw new IOException("File is too large for one binary read: " + length + " bytes. Limit is " + MAX_BINARY_BYTES + " bytes.");
        }
        return Base64.getEncoder().encodeToString(Files.readAllBytes(file.toPath()));
    }

    String writeFileBase64(String path, String contentBase64) throws IOException {
        File file = resolvePath(path);
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode((contentBase64 == null ? "" : contentBase64).replaceAll("\\s", ""));
        } catch (IllegalArgumentException error) {
            throw new IOException("Invalid base64 content.", error);
        }
        File parent = file.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("Could not create parent directory: " + pathForUser(parent));
        }
        Files.write(file.toPath(), bytes);
        return "Wrote binary " + pathForUser(file) + " (" + file.length() + " bytes)";
    }

    String readFileChunkBase64(String path, long offset, int length) throws IOException, JSONException {
        File file = resolvePath(path);
        if (!file.isFile()) {
            throw new IOException("Not a file: " + pathForUser(file));
        }
        if (offset < 0) {
            throw new IOException("offset must be >= 0");
        }
        if (length <= 0 || length > MAX_CHUNK_BYTES) {
            throw new IOException("length must be between 1 and " + MAX_CHUNK_BYTES + " bytes.");
        }
        long fileLength = file.length();
        if (offset > fileLength) {
            throw new IOException("offset is beyond end of file. File size is " + fileLength + " bytes.");
        }
        int bytesToRead = (int) Math.min((long) length, fileLength - offset);
        byte[] buffer = new byte[bytesToRead];
        try (RandomAccessFile randomAccessFile = new RandomAccessFile(file, "r")) {
            randomAccessFile.seek(offset);
            if (bytesToRead > 0) {
                randomAccessFile.readFully(buffer);
            }
        }
        JSONObject output = new JSONObject();
        output.put("path", pathForUser(file));
        output.put("offset", offset);
        output.put("requestedBytes", length);
        output.put("bytesRead", bytesToRead);
        output.put("fileBytes", fileLength);
        output.put("nextOffset", offset + bytesToRead);
        output.put("eof", offset + bytesToRead >= fileLength);
        output.put("content_base64", Base64.getEncoder().encodeToString(buffer));
        return output.toString();
    }

    String writeFileChunkBase64(String path, long offset, String contentBase64, boolean truncateBeforeWrite, boolean truncateAfterWrite) throws IOException, JSONException {
        File file = resolvePath(path);
        if (offset < 0) {
            throw new IOException("offset must be >= 0");
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode((contentBase64 == null ? "" : contentBase64).replaceAll("\\s", ""));
        } catch (IllegalArgumentException error) {
            throw new IOException("Invalid base64 content.", error);
        }
        if (bytes.length > MAX_CHUNK_BYTES) {
            throw new IOException("Chunk is too large: " + bytes.length + " bytes. Limit is " + MAX_CHUNK_BYTES + " bytes.");
        }
        File parent = file.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("Could not create parent directory: " + pathForUser(parent));
        }
        boolean existed = file.exists();
        if (!existed && offset != 0) {
            throw new IOException("First chunk for a new file must use offset 0.");
        }
        try (RandomAccessFile randomAccessFile = new RandomAccessFile(file, "rw")) {
            if (!truncateBeforeWrite && offset > randomAccessFile.length()) {
                throw new IOException("offset is beyond current file size. Current size is " + randomAccessFile.length() + " bytes.");
            }
            if (truncateBeforeWrite) {
                randomAccessFile.setLength(offset);
            }
            randomAccessFile.seek(offset);
            randomAccessFile.write(bytes);
            if (truncateAfterWrite) {
                randomAccessFile.setLength(offset + bytes.length);
            }
        }
        JSONObject output = new JSONObject();
        output.put("path", pathForUser(file));
        output.put("offset", offset);
        output.put("bytesWritten", bytes.length);
        output.put("fileBytes", file.length());
        output.put("nextOffset", offset + bytes.length);
        return output.toString();
    }

    String hashFile(String path, String algorithm) throws IOException, JSONException {
        File file = resolvePath(path);
        if (!file.isFile()) {
            throw new IOException("Not a file: " + pathForUser(file));
        }
        String normalizedAlgorithm = algorithm == null || algorithm.isEmpty() ? "SHA-256" : algorithm.toUpperCase(Locale.ROOT);
        if ("SHA256".equals(normalizedAlgorithm)) {
            normalizedAlgorithm = "SHA-256";
        }
        if (!"SHA-256".equals(normalizedAlgorithm)) {
            throw new IOException("Unsupported hash algorithm: " + algorithm + ". Supported: SHA-256");
        }
        MessageDigest digest;
        try {
            digest = MessageDigest.getInstance(normalizedAlgorithm);
        } catch (Exception error) {
            throw new IOException("Hash algorithm unavailable: " + normalizedAlgorithm, error);
        }
        byte[] buffer = new byte[1024 * 1024];
        try (FileInputStream input = new FileInputStream(file)) {
            int read;
            while ((read = input.read(buffer)) != -1) {
                digest.update(buffer, 0, read);
            }
        }
        JSONObject output = new JSONObject();
        output.put("path", pathForUser(file));
        output.put("bytes", file.length());
        output.put("algorithm", normalizedAlgorithm);
        output.put("hash", toHex(digest.digest()));
        return output.toString();
    }

    String listDirectory(String path) throws IOException {
        File dir = resolvePath(path == null || path.isEmpty() ? "." : path);
        if (!dir.isDirectory()) {
            throw new IOException("Not a directory: " + pathForUser(dir));
        }
        File[] entries = dir.listFiles();
        if (entries == null) {
            throw new IOException("Could not list directory: " + pathForUser(dir));
        }
        List<File> files = new ArrayList<>(List.of(entries));
        files.sort(Comparator.comparing((File file) -> !file.isDirectory()).thenComparing(File::getName, String.CASE_INSENSITIVE_ORDER));
        StringBuilder out = new StringBuilder();
        out.append(pathForUser(dir)).append("\n");
        for (File file : files) {
            out.append(file.isDirectory() ? "dir  " : "file ");
            out.append(String.format(Locale.US, "%10d  ", file.isDirectory() ? 0 : file.length()));
            out.append(file.getName()).append("\n");
        }
        return out.toString();
    }

    String grepFiles(String pattern, String path) throws IOException {
        if (pattern == null || pattern.isEmpty()) {
            throw new IOException("pattern is required");
        }
        File start = resolvePath(path == null || path.isEmpty() ? "." : path);
        String needle = pattern.toLowerCase(Locale.ROOT);
        StringBuilder out = new StringBuilder();
        int matches = 0;
        ArrayDeque<File> queue = new ArrayDeque<>();
        queue.add(start);
        while (!queue.isEmpty() && matches < MAX_GREP_MATCHES) {
            File current = queue.removeFirst();
            if (current.isDirectory()) {
                File[] children = current.listFiles();
                if (children == null) {
                    continue;
                }
                for (File child : children) {
                    if (!child.isHidden()) {
                        queue.addLast(child);
                    }
                }
                continue;
            }
            if (!current.isFile() || current.length() > MAX_READ_BYTES) {
                continue;
            }
            List<String> lines;
            try {
                lines = Files.readAllLines(current.toPath(), StandardCharsets.UTF_8);
            } catch (IOException ignored) {
                continue;
            }
            for (int i = 0; i < lines.size() && matches < MAX_GREP_MATCHES; i++) {
                String line = lines.get(i);
                if (line.toLowerCase(Locale.ROOT).contains(needle)) {
                    out.append(relativePath(current)).append(":").append(i + 1).append(":").append(line).append("\n");
                    matches++;
                }
            }
        }
        if (matches == 0) {
            return "No matches.";
        }
        if (matches >= MAX_GREP_MATCHES) {
            out.append("Stopped after ").append(MAX_GREP_MATCHES).append(" matches.\n");
        }
        return out.toString();
    }

    String findFiles(String query, String path, int limit) throws IOException {
        if (query == null || query.isEmpty()) {
            throw new IOException("query is required");
        }
        int maxResults = limit <= 0 ? 100 : Math.min(limit, MAX_FIND_RESULTS);
        File start = resolvePath(path == null || path.isEmpty() ? "." : path);
        String needle = query.toLowerCase(Locale.ROOT);
        StringBuilder out = new StringBuilder();
        int matches = 0;
        ArrayDeque<File> queue = new ArrayDeque<>();
        queue.add(start);
        while (!queue.isEmpty() && matches < maxResults) {
            File current = queue.removeFirst();
            String relative = relativePath(current);
            String haystack = (relative + "/" + current.getName()).toLowerCase(Locale.ROOT);
            if (haystack.contains(needle)) {
                out.append(current.isDirectory() ? "dir  " : "file ");
                out.append(pathForUser(current));
                if (current.isFile()) {
                    out.append(" (").append(current.length()).append(" bytes)");
                }
                out.append("\n");
                matches++;
            }
            if (current.isDirectory()) {
                File[] children = current.listFiles();
                if (children == null) {
                    continue;
                }
                for (File child : children) {
                    if (!child.isHidden()) {
                        queue.addLast(child);
                    }
                }
            }
        }
        if (matches == 0) {
            return "No matches.";
        }
        if (matches >= maxResults) {
            out.append("Stopped after ").append(maxResults).append(" matches.\n");
        }
        return out.toString();
    }

    String scanMedia(String path, boolean recursive) throws IOException, JSONException {
        File target = resolvePath(path == null || path.isEmpty() ? "." : path);
        if (!target.exists()) {
            throw new IOException("Path does not exist: " + pathForUser(target));
        }
        List<String> paths = new ArrayList<>();
        if (target.isFile()) {
            paths.add(target.getAbsolutePath());
        } else if (target.isDirectory()) {
            if (!recursive) {
                throw new IOException("Path is a directory. Set recursive=true to scan contained files.");
            }
            collectMediaScanFiles(target, paths);
        }
        if (paths.isEmpty()) {
            return new JSONObject()
                .put("path", pathForUser(target))
                .put("queued", 0)
                .put("message", "No files queued for media scan.")
                .toString();
        }
        MediaScannerConnection.scanFile(context, paths.toArray(new String[0]), null, null);
        JSONObject output = new JSONObject();
        output.put("path", pathForUser(target));
        output.put("queued", paths.size());
        output.put("recursive", recursive);
        output.put("limit", MAX_MEDIA_SCAN_FILES);
        output.put("message", "Queued Android media scan. Gallery/media apps may update asynchronously.");
        return output.toString();
    }

    String zipPaths(JSONArray paths, String outputPath, boolean overwrite) throws IOException, JSONException {
        if (paths == null || paths.length() == 0) {
            throw new IOException("paths is required");
        }
        File output = resolvePath(outputPath);
        if (output.exists() && !overwrite) {
            throw new IOException("Output already exists: " + pathForUser(output));
        }
        File parent = output.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("Could not create output parent: " + pathForUser(parent));
        }
        File root = allowedRoot().getCanonicalFile();
        File canonicalOutput = output.getCanonicalFile();
        ZipState state = new ZipState();
        try (ZipOutputStream zip = new ZipOutputStream(new FileOutputStream(output))) {
            for (int i = 0; i < paths.length(); i++) {
                String sourcePath = paths.optString(i, "");
                if (sourcePath.isEmpty()) {
                    continue;
                }
                File source = resolvePath(sourcePath);
                if (!source.exists()) {
                    throw new IOException("Source does not exist: " + pathForUser(source));
                }
                ensureNotRoot(source, "zip");
                addZipEntry(root, source, canonicalOutput, zip, state);
            }
        } catch (IOException error) {
            if (output.exists()) {
                Files.deleteIfExists(output.toPath());
            }
            throw error;
        }
        JSONObject result = new JSONObject();
        result.put("output", pathForUser(output));
        result.put("entries", state.entries);
        result.put("inputBytes", state.bytes);
        result.put("zipBytes", output.length());
        return result.toString();
    }

    String unzipFile(String zipPath, String destinationPath, boolean overwrite) throws IOException, JSONException {
        File zipFile = resolvePath(zipPath);
        if (!zipFile.isFile()) {
            throw new IOException("Not a zip file: " + pathForUser(zipFile));
        }
        File destination = resolvePath(destinationPath);
        if (destination.exists() && !destination.isDirectory()) {
            throw new IOException("Destination exists and is not a directory: " + pathForUser(destination));
        }
        if (!destination.exists() && !destination.mkdirs()) {
            throw new IOException("Could not create destination directory: " + pathForUser(destination));
        }
        File allowedRoot = allowedRoot().getCanonicalFile();
        File canonicalDestination = destination.getCanonicalFile();
        ZipState state = new ZipState();
        byte[] buffer = new byte[8192];
        try (ZipInputStream zip = new ZipInputStream(new FileInputStream(zipFile))) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                String name = entry.getName() == null ? "" : entry.getName().replace('\\', '/');
                if (name.isEmpty() || name.startsWith("/") || name.contains("../")) {
                    throw new IOException("Unsafe zip entry path: " + name);
                }
                File target = new File(destination, name).getCanonicalFile();
                if (!target.toPath().startsWith(canonicalDestination.toPath()) || !target.toPath().startsWith(allowedRoot.toPath())) {
                    throw new IOException("Zip entry escapes destination: " + name);
                }
                state.checkEntry(0);
                if (entry.isDirectory()) {
                    if (!target.exists() && !target.mkdirs()) {
                        throw new IOException("Could not create directory: " + pathForUser(target));
                    }
                    zip.closeEntry();
                    continue;
                }
                File parent = target.getParentFile();
                if (parent != null && !parent.exists() && !parent.mkdirs()) {
                    throw new IOException("Could not create parent directory: " + pathForUser(parent));
                }
                if (target.exists() && !overwrite) {
                    throw new IOException("Destination file already exists: " + pathForUser(target));
                }
                try (FileOutputStream output = new FileOutputStream(target, false)) {
                    int read;
                    while ((read = zip.read(buffer)) != -1) {
                        state.addBytes(read);
                        output.write(buffer, 0, read);
                    }
                }
                zip.closeEntry();
            }
        }
        JSONObject result = new JSONObject();
        result.put("zip", pathForUser(zipFile));
        result.put("destination", pathForUser(destination));
        result.put("entries", state.entries);
        result.put("outputBytes", state.bytes);
        return result.toString();
    }

    String makeDirectory(String path) throws IOException {
        File dir = resolvePath(path);
        if (dir.exists() && !dir.isDirectory()) {
            throw new IOException("Path already exists and is not a directory: " + pathForUser(dir));
        }
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IOException("Could not create directory: " + pathForUser(dir));
        }
        return "Directory ready: " + pathForUser(dir);
    }

    String deletePath(String path, boolean recursive) throws IOException {
        File target = resolvePath(path);
        if (!target.exists()) {
            throw new IOException("Path does not exist: " + pathForUser(target));
        }
        ensureNotRoot(target, "delete");
        if (target.isDirectory() && recursive) {
            deleteRecursive(target);
        } else {
            Files.delete(target.toPath());
        }
        return "Deleted " + pathForUser(target);
    }

    String movePath(String fromPath, String toPath, boolean overwrite) throws IOException {
        File from = resolvePath(fromPath);
        File to = resolvePath(toPath);
        if (!from.exists()) {
            throw new IOException("Source does not exist: " + pathForUser(from));
        }
        ensureNotRoot(from, "move");
        if (to.exists()) {
            if (!overwrite) {
                throw new IOException("Destination already exists: " + pathForUser(to));
            }
            ensureNotRoot(to, "overwrite");
            if (to.isDirectory()) {
                deleteRecursive(to);
            } else {
                Files.delete(to.toPath());
            }
        }
        File parent = to.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("Could not create destination parent: " + pathForUser(parent));
        }
        Files.move(from.toPath(), to.toPath(), StandardCopyOption.REPLACE_EXISTING);
        return "Moved " + pathForUser(from) + " -> " + pathForUser(to);
    }

    String copyPath(String fromPath, String toPath, boolean recursive, boolean overwrite) throws IOException {
        File from = resolvePath(fromPath);
        File to = resolvePath(toPath);
        if (!from.exists()) {
            throw new IOException("Source does not exist: " + pathForUser(from));
        }
        if (to.exists() && !overwrite) {
            throw new IOException("Destination already exists: " + pathForUser(to));
        }
        if (from.isDirectory()) {
            if (!recursive) {
                throw new IOException("Source is a directory. Set recursive=true to copy it.");
            }
            copyDirectory(from, to, overwrite);
        } else {
            copyFile(from, to, overwrite);
        }
        return "Copied " + pathForUser(from) + " -> " + pathForUser(to);
    }

    String statPath(String path) throws IOException {
        File file = resolvePath(path == null || path.isEmpty() ? "." : path);
        StringBuilder out = new StringBuilder();
        out.append("Path: ").append(pathForUser(file)).append("\n");
        out.append("Relative: ").append(relativePath(file)).append("\n");
        out.append("Exists: ").append(file.exists()).append("\n");
        if (file.exists()) {
            out.append("Type: ").append(file.isDirectory() ? "directory" : file.isFile() ? "file" : "other").append("\n");
            out.append("Bytes: ").append(file.isDirectory() ? 0 : file.length()).append("\n");
            out.append("Last modified: ").append(file.lastModified()).append("\n");
            out.append("Readable: ").append(file.canRead()).append("\n");
            out.append("Writable: ").append(file.canWrite()).append("\n");
            out.append("Hidden: ").append(file.isHidden()).append("\n");
        }
        return out.toString();
    }

    File resolvePath(String path) throws IOException {
        File root = allowedRoot().getCanonicalFile();
        String requested = normalizeRequestedPath(root, path);
        String normalizedRequested = stripTrailingSlashes(requested);
        String rootPath = root.getAbsolutePath();
        String rootPathWithoutLeadingSlash = rootPath.startsWith("/") ? rootPath.substring(1) : rootPath;
        File target;
        if (".".equals(requested) || "/".equals(requested) || rootPath.equals(normalizedRequested) || rootPathWithoutLeadingSlash.equals(normalizedRequested)) {
            target = root;
        } else if (normalizedRequested.startsWith(rootPath + "/")) {
            target = new File(normalizedRequested).getCanonicalFile();
        } else if (normalizedRequested.startsWith(rootPathWithoutLeadingSlash + "/")) {
            target = new File("/" + normalizedRequested).getCanonicalFile();
        } else if (requested.startsWith("/")) {
            target = new File(requested).getCanonicalFile();
        } else {
            target = new File(root, requested).getCanonicalFile();
        }
        if (!target.toPath().startsWith(root.toPath())) {
            throw new IOException("Path escapes allowed root: " + path);
        }
        return target;
    }

    private String normalizeRequestedPath(File root, String path) {
        String requested = path == null || path.isEmpty() ? "." : path.trim().replace('\\', '/');
        String normalized = stripTrailingSlashes(requested);
        String rootPath = root.getAbsolutePath().replace('\\', '/');
        String rootPathWithoutLeadingSlash = rootPath.startsWith("/") ? rootPath.substring(1) : rootPath;
        if (".".equals(normalized) || "/".equals(normalized) || rootPath.equals(normalized) || rootPathWithoutLeadingSlash.equals(normalized)) {
            return ".";
        }
        if (normalized.startsWith(rootPath + "/")) {
            return normalized.substring(rootPath.length() + 1);
        }
        if (normalized.startsWith(rootPathWithoutLeadingSlash + "/")) {
            return normalized.substring(rootPathWithoutLeadingSlash.length() + 1);
        }
        return requested;
    }

    private String stripTrailingSlashes(String path) {
        String normalized = path;
        while (normalized.length() > 1 && normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        return normalized;
    }

    private String relativePath(File file) throws IOException {
        File root = allowedRoot().getCanonicalFile();
        File target = file.getCanonicalFile();
        return root.toPath().relativize(target.toPath()).toString();
    }

    private String pathForUser(File file) {
        return file.getAbsolutePath();
    }

    private void deleteRecursive(File target) throws IOException {
        ensureNotRoot(target, "delete");
        File[] children = target.listFiles();
        if (children != null) {
            for (File child : children) {
                if (child.isDirectory()) {
                    deleteRecursive(child);
                } else {
                    Files.delete(child.toPath());
                }
            }
        }
        Files.delete(target.toPath());
    }

    private void copyDirectory(File from, File to, boolean overwrite) throws IOException {
        if (to.exists() && !to.isDirectory()) {
            if (!overwrite) {
                throw new IOException("Destination already exists and is not a directory: " + pathForUser(to));
            }
            Files.delete(to.toPath());
        }
        if (!to.exists() && !to.mkdirs()) {
            throw new IOException("Could not create destination directory: " + pathForUser(to));
        }
        File[] children = from.listFiles();
        if (children == null) {
            throw new IOException("Could not list source directory: " + pathForUser(from));
        }
        for (File child : children) {
            File childTo = new File(to, child.getName());
            if (child.isDirectory()) {
                copyDirectory(child, childTo, overwrite);
            } else {
                copyFile(child, childTo, overwrite);
            }
        }
    }

    private void copyFile(File from, File to, boolean overwrite) throws IOException {
        File parent = to.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("Could not create destination parent: " + pathForUser(parent));
        }
        if (overwrite) {
            Files.copy(from.toPath(), to.toPath(), StandardCopyOption.REPLACE_EXISTING);
        } else {
            Files.copy(from.toPath(), to.toPath());
        }
    }

    private void ensureNotRoot(File target, String operation) throws IOException {
        File root = allowedRoot().getCanonicalFile();
        File canonicalTarget = target.getCanonicalFile();
        if (canonicalTarget.equals(root)) {
            throw new IOException("Refusing to " + operation + " the allowed root: " + pathForUser(root));
        }
    }

    private void collectMediaScanFiles(File start, List<String> paths) {
        ArrayDeque<File> queue = new ArrayDeque<>();
        queue.add(start);
        while (!queue.isEmpty() && paths.size() < MAX_MEDIA_SCAN_FILES) {
            File current = queue.removeFirst();
            if (current.isFile()) {
                paths.add(current.getAbsolutePath());
                continue;
            }
            if (!current.isDirectory()) {
                continue;
            }
            File[] children = current.listFiles();
            if (children == null) {
                continue;
            }
            for (File child : children) {
                if (!child.isHidden()) {
                    queue.addLast(child);
                }
            }
        }
    }

    private void addZipEntry(File root, File source, File output, ZipOutputStream zip, ZipState state) throws IOException {
        File canonicalSource = source.getCanonicalFile();
        if (canonicalSource.equals(output)) {
            return;
        }
        String entryName = root.toPath().relativize(canonicalSource.toPath()).toString().replace(File.separatorChar, '/');
        if (source.isDirectory()) {
            File[] children = source.listFiles();
            if (children == null || children.length == 0) {
                state.checkEntry(0);
                zip.putNextEntry(new ZipEntry(entryName.endsWith("/") ? entryName : entryName + "/"));
                zip.closeEntry();
                return;
            }
            for (File child : children) {
                if (!child.isHidden()) {
                    addZipEntry(root, child, output, zip, state);
                }
            }
            return;
        }
        if (!source.isFile()) {
            return;
        }
        state.checkEntry(source.length());
        zip.putNextEntry(new ZipEntry(entryName));
        byte[] buffer = new byte[8192];
        try (FileInputStream input = new FileInputStream(source)) {
            int read;
            while ((read = input.read(buffer)) != -1) {
                zip.write(buffer, 0, read);
            }
        }
        zip.closeEntry();
    }

    private static final class ZipState {
        int entries;
        long bytes;

        void checkEntry(long addedBytes) throws IOException {
            if (entries >= MAX_ZIP_ENTRIES) {
                throw new IOException("Zip entry limit exceeded: " + MAX_ZIP_ENTRIES);
            }
            entries++;
            addBytes(addedBytes);
        }

        void addBytes(long addedBytes) throws IOException {
            bytes += Math.max(0L, addedBytes);
            if (bytes > MAX_ZIP_BYTES) {
                throw new IOException("Zip byte limit exceeded: " + MAX_ZIP_BYTES);
            }
        }
    }

    private String toHex(byte[] bytes) {
        StringBuilder out = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) {
            out.append(String.format(Locale.US, "%02x", value & 0xff));
        }
        return out.toString();
    }

    private void addKnownRoot(StringBuilder out, String label, File file) {
        out.append(label).append(": ").append(file.getAbsolutePath());
        out.append(file.exists() ? " (exists)" : " (not present)");
        out.append("\n");
    }
}
