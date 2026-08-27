import os
import tempfile
from zipfile import ZipFile

from django.test import SimpleTestCase

from process_pipeline.functions.result_files import build_zip_file


class TestBuildZipFile(SimpleTestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp_dir.cleanup)

    def _write(self, relative_path: str, content: bytes = b"data") -> str:
        path = os.path.join(self.tmp_dir.name, relative_path)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(content)
        return path

    def test_writes_each_file_under_its_base_name(self):
        paths = [self._write("a/first.csv"), self._write("b/second.csv")]

        result = build_zip_file(paths, "export.zip")

        with ZipFile(result) as zip_file:
            self.assertEqual(sorted(zip_file.namelist()), ["first.csv", "second.csv"])

    def test_keeps_the_file_contents(self):
        paths = [self._write("a/first.csv", b"col1,col2\n")]

        result = build_zip_file(paths, "export.zip")

        with ZipFile(result) as zip_file:
            self.assertEqual(zip_file.read("first.csv"), b"col1,col2\n")

    def test_keeps_unique_relative_paths_in_zip(self):
        paths = [self._write("a/report.csv"), self._write("b/report.csv")]

        result = build_zip_file(paths, "export.zip")

        with ZipFile(result) as zip_file:
            self.assertEqual(sorted(zip_file.namelist()), ["a/report.csv", "b/report.csv"])

    def test_keeps_multiple_relative_paths_in_zip(self):
        paths = [
            self._write("a/report.csv"),
            self._write("b/report.csv"),
            self._write("a/summary.csv"),
            self._write("b/summary.csv"),
        ]

        result = build_zip_file(paths, "export.zip")

        with ZipFile(result) as zip_file:
            self.assertEqual(
                sorted(zip_file.namelist()),
                [
                    "a/report.csv",
                    "a/summary.csv",
                    "b/report.csv",
                    "b/summary.csv",
                ],
            )
