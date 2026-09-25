"""Exercise the build-time patch without modifying the upstream checkout."""
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

PLUGIN = pathlib.Path(__file__).resolve().parents[2]
PATCH = PLUGIN / 'windows/patches/windows-unicode-nnue.cmake'
UPSTREAM = PLUGIN / 'ios/Pikafish/src/misc.cpp'


class NnuePatchTest(unittest.TestCase):
    def run_patch(self, source, output):
        return subprocess.run(
            ['cmake', f'-DINPUT={source}', f'-DOUTPUT={output}', '-P', str(PATCH)],
            capture_output=True, text=True,
        )

    def test_real_source_lf_and_crlf_and_repeat(self):
        original = UPSTREAM.read_bytes()
        for newline in ('\n', '\r\n'):
            with self.subTest(newline=newline), tempfile.TemporaryDirectory() as temp:
                root = pathlib.Path(temp) / '中文 模型测试'
                root.mkdir()
                source = root / 'upstream.cpp'
                source.write_bytes(UPSTREAM.read_text().replace('\n', newline).encode())
                before = source.read_bytes()
                output = root / 'generated/misc.cpp'
                result = self.run_patch(source, output)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(source.read_bytes(), before)
                patched = output.read_text()
                self.assertEqual(patched.count('std::filesystem::u8path(fpath)'), 1)
                self.assertIn('#include <filesystem>', patched)
                # The original narrow open remains only in the non-Windows branch.
                self.assertIn('#else\n    std::ifstream fin(fpath, std::ios::binary);', patched)
                timestamp = output.stat().st_mtime_ns
                result = self.run_patch(source, output)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(output.stat().st_mtime_ns, timestamp)
        self.assertEqual(UPSTREAM.read_bytes(), original)

    def test_upstream_changes_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            source = pathlib.Path(temp) / 'misc.cpp'
            source.write_text(UPSTREAM.read_text().replace(
                'std::ifstream fin(fpath, std::ios::binary);',
                'std::ifstream fin(new_path, std::ios::binary);'))
            output = pathlib.Path(temp) / 'generated.cpp'
            result = self.run_patch(source, output)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('no longer matches', result.stderr)
            self.assertFalse(output.exists())

    def test_custom_command_include_paths_with_unicode_and_spaces(self):
        compiler = shutil.which('clang++') or shutil.which('g++')
        if compiler is None:
            self.skipTest('A GNU-style C++ compiler is required for the include-path probe')
        cmake_source = (PLUGIN / 'windows/CMakeLists.txt').read_text()
        flags = re.search(r'  set\(_engine_flags\b.*?\n  \)', cmake_source, re.S)
        self.assertIsNotNone(flags)
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp) / '中文 编译测试'
            headers = root / '引擎 源码'
            external = headers / 'external'
            ffi = root / 'FFI 封装'
            external.mkdir(parents=True)
            ffi.mkdir()
            (headers / 'misc.h').write_text('#define TEST_MISC 1\n')
            (external / 'external_probe.h').write_text('#define TEST_EXTERNAL 2\n')
            (ffi / 'ffi_probe.h').write_text('#define TEST_FFI 3\n')
            (root / 'probe.cpp').write_text(
                '#include "misc.h"\n#include "external_probe.h"\n'
                '#include "ffi_probe.h"\n'
                'static_assert(TEST_MISC + TEST_EXTERNAL + TEST_FFI == 6);\n')
            # Use the real flag definition and the same custom-command escaping.
            # Only platform-specific compilation/assembler flags are excluded.
            (root / 'CMakeLists.txt').write_text(
                'cmake_minimum_required(VERSION 3.14)\nproject(include_probe NONE)\n'
                f'set(PIKAFISH_SRC_DIR "{headers.as_posix()}")\n'
                f'set(PIKAFISH_FFI_DIR "{ffi.as_posix()}")\n'
                + flags.group() + '\n'
                'list(FILTER _engine_flags INCLUDE REGEX "^-I")\n'
                'add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/probe.o"\n'
                f' COMMAND "{pathlib.Path(compiler).as_posix()}" ${{_engine_flags}}'
                ' -std=c++17 -c "${CMAKE_CURRENT_SOURCE_DIR}/probe.cpp"'
                ' -o "${CMAKE_CURRENT_BINARY_DIR}/probe.o"\n'
                ' VERBATIM COMMAND_EXPAND_LISTS)\n'
                'add_custom_target(probe ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/probe.o")\n')
            build = root / 'build'
            result = subprocess.run(['cmake', '-S', str(root), '-B', str(build)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run(['cmake', '--build', str(build)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_refuses_to_overwrite_input(self):
        with tempfile.TemporaryDirectory() as temp:
            source = pathlib.Path(temp) / 'misc.cpp'
            original = UPSTREAM.read_bytes()
            source.write_bytes(original)
            result = self.run_patch(source, source)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(source.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
